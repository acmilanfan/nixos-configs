#!/usr/bin/env bash
# Regression tests for darwin/scripts/kanata-ctl.sh.
# Run: bash tests/kanata/test_kanata_ctl.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SCRIPT="$ROOT/darwin/scripts/kanata-ctl.sh"
FIXTURE=$(mktemp -d "$HOME/ai/artifacts/nixos-configs/kanata-tests.XXXXXX" 2>/dev/null || mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
CALLS="$FIXTURE/calls"
: > "$CALLS"

fail() {
    echo "kanata-ctl: $*" >&2
    exit 1
}

# Functions shadow external commands, so the helper can be exercised without
# root or a live launchd/HID stack.
hidutil() { printf '%s\n' "${HIDUTIL_OUTPUT:-}"; }
launchctl() {
    printf 'launchctl %s\n' "$*" >> "$CALLS"
    case "$1" in
        bootout)
            RUNNING=0
            PHASE=stop
            STOP_CHECKS=0
            ;;
        bootstrap)
            RUNNING=1
            PHASE=start
            if [ "${FAIL_BOOTSTRAP:-0}" = 1 ]; then
                RUNNING=0
                return 1
            fi
            ;;
    esac
    return 0
}
pgrep() {
    printf 'pgrep %s\n' "$*" >> "$CALLS"
    if [ "$PHASE" = stop ]; then
        STOP_CHECKS=$((STOP_CHECKS + 1))
        [ "$STOP_CHECKS" -le 2 ] || return 1
        printf '%s\n' "${PGREP_PID:-75297}"
        return 0
    fi
    [ "$RUNNING" = 1 ] || return 1
    printf '%s\n' "${PGREP_PID:-75297}"
    return 0
}
ioreg() { cat "${IOREG_FIXTURE:-/dev/null}"; }
pkill() { printf 'pkill %s\n' "$*" >> "$CALLS"; }
sleep() { printf 'sleep %s\n' "$*" >> "$CALLS"; }

RUNNING=0
PHASE=start
STOP_CHECKS=0

# shellcheck source=/dev/null
source "$SCRIPT"

# ensure_hid repairs a missing virtual keyboard and reports the restart.
: > "$CALLS"
HIDUTIL_OUTPUT=""
out=$(ensure_hid)
[ "$out" = restarted ] || fail "ensure_hid should report restarted (got '$out')"
grep -qx 'launchctl kickstart -k system/org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon' "$CALLS" \
    || fail "ensure_hid did not kickstart the VirtualHID daemon"

# ensure_hid is silent and does not touch the daemon when the device exists.
: > "$CALLS"
HIDUTIL_OUTPUT="Karabiner DriverKit VirtualHIDKeyboard 1.8.0"
out=$(ensure_hid)
[ -z "$out" ] || fail "ensure_hid should be quiet when present (got '$out')"
! grep -q kickstart "$CALLS" || fail "ensure_hid kickstarted despite a present device"

# health proves the input grab is really attached. A param/enumeration client
# is not enough: after a DarkWake the grab can vanish while the process and
# output sink stay alive (upstream #2094).
cat > "$FIXTURE/lib-ok.txt" <<'EOF'
    | |   +-o IOHIDLibUserClient  <class IOHIDLibUserClient, id 0x1, active>
    | |       "IOUserClientCreator" = "pid 75297, kanata-nix"
    | |       "DebugState" = {"ClientOpened"=Yes}
EOF
cat > "$FIXTURE/param-only.txt" <<'EOF'
    | |   +-o IOHIDParamUserClient  <class IOHIDParamUserClient, id 0x1, active>
    | |   |   "IOUserClientCreator" = "pid 75297, kanata-nix"
    | |   |   "DebugState" = {"ClientOpened"=Yes}
EOF
cat > "$FIXTURE/lib-other.txt" <<'EOF'
    | |   +-o IOHIDLibUserClient  <class IOHIDLibUserClient, id 0x1, active>
    | |       "IOUserClientCreator" = "pid 99999, other"
    | |       "DebugState" = {"ClientOpened"=Yes}
EOF

: > "$CALLS"
RUNNING=1
PHASE=start
IOREG_FIXTURE="$FIXTURE/lib-ok.txt"
health || fail "health should pass with a kanata-owned IOHIDLibUserClient"

: > "$CALLS"
IOREG_FIXTURE="$FIXTURE/param-only.txt"
if health 2> "$FIXTURE/health.err"; then
    fail "health should fail when only the enumeration client remains"
fi
grep -q 'input grab not present' "$FIXTURE/health.err" || fail "no health failure message"
grep -q '^sleep 0.5$' "$CALLS" || fail "health did not wait for native recovery"

: > "$CALLS"
IOREG_FIXTURE="$FIXTURE/lib-other.txt"
if health 2>/dev/null; then
    fail "health should ignore a client owned by another process"
fi

: > "$CALLS"
IOREG_FIXTURE="$FIXTURE/lib-ok.txt"
main health || fail "main health dispatch failed"

# restart stops the old instance, waits for it to release the keyboard,
# settles, and only then starts the replacement.
: > "$CALLS"
RUNNING=1
PHASE=start
STOP_CHECKS=0
restart_kanata || fail "restart_kanata failed"
grep -qx 'launchctl bootout system/local.kanata' "$CALLS" || fail "no bootout"
grep -qx 'launchctl bootstrap system /Library/LaunchDaemons/local.kanata.plist' "$CALLS" \
    || fail "no bootstrap"
! grep -q 'kickstart -k system/local.kanata' "$CALLS" || fail "restart still uses kickstart -k"

boot_line=$(grep -n '^launchctl bootout' "$CALLS" | cut -d: -f1 || true)
start_line=$(grep -n '^launchctl bootstrap' "$CALLS" | cut -d: -f1 || true)
[ "$boot_line" -lt "$start_line" ] || fail "bootstrap ran before bootout"
awk -v b="$boot_line" -v s="$start_line" \
    'NR > b && NR < s && /^sleep 1$/ { found = 1 } END { exit found ? 0 : 1 }' "$CALLS" \
    || fail "no settle delay between bootout and bootstrap"
awk -v b="$boot_line" -v s="$start_line" \
    'NR > b && NR < s && /^sleep 0.1$/ { n++ } END { exit n >= 2 ? 0 : 1 }' "$CALLS" \
    || fail "restart did not wait for the old process to exit"

# A failed start is reported, not silently ignored.
: > "$CALLS"
RUNNING=1
PHASE=start
STOP_CHECKS=0
FAIL_BOOTSTRAP=1
if restart_kanata 2> "$FIXTURE/err"; then
    fail "restart_kanata should fail when the service cannot start"
fi
grep -q 'failed to start local.kanata' "$FIXTURE/err" || fail "no failure message"
FAIL_BOOTSTRAP=0

# rescue stops kanata, repairs the HID stack, then starts it again; it must
# not rely on KeepAlive racing the daemon reset.
: > "$CALLS"
RUNNING=1
PHASE=start
STOP_CHECKS=0
neutralize() { printf 'neutralize\n' >> "$CALLS"; }
reset_hid() { printf 'reset-hid\n' >> "$CALLS"; }
main rescue || fail "rescue failed"
grep -qx neutralize "$CALLS" || fail "rescue did not neutralize"
grep -qx reset-hid "$CALLS" || fail "rescue did not reset the HID stack"
neutral_line=$(grep -n '^neutralize$' "$CALLS" | cut -d: -f1 || true)
boot_line=$(grep -n '^launchctl bootout' "$CALLS" | cut -d: -f1 || true)
reset_line=$(grep -n '^reset-hid$' "$CALLS" | cut -d: -f1 || true)
start_line=$(grep -n '^launchctl bootstrap' "$CALLS" | cut -d: -f1 || true)
[ "$neutral_line" -lt "$boot_line" ] && [ "$boot_line" -lt "$reset_line" ] \
    && [ "$reset_line" -lt "$start_line" ] \
    || fail "rescue ran in the wrong order"

# The installed entrypoint still dispatches (and does not run from a source).
if bash "$SCRIPT" > /dev/null 2> "$FIXTURE/usage"; then
    fail "kanata-ctl without arguments should exit non-zero"
fi
grep -q usage "$FIXTURE/usage" || fail "kanata-ctl without arguments should print usage"

echo "kanata-ctl: all cases passed"
