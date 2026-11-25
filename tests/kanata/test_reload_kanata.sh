#!/usr/bin/env bash
# Regression tests for dotfiles/kanata/reload-kanata.sh.
# Run: bash tests/kanata/test_reload_kanata.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SCRIPT="$ROOT/dotfiles/kanata/reload-kanata.sh"
FIXTURE=$(mktemp -d "$HOME/ai/artifacts/nixos-configs/kanata-tests.XXXXXX" 2>/dev/null || mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
export CALLS="$FIXTURE/calls"
: > "$CALLS"

fail() {
    echo "reload-kanata: $*" >&2
    exit 1
}

cat > "$FIXTURE/kanata-ctl" <<'SH'
#!/usr/bin/env bash
printf 'kanata-ctl %s\n' "$*" >> "$CALLS"
if [ "$1" = ensure-hid ] && [ "${STUB_ENSURE_RESTARTED:-1}" = 1 ]; then
    printf 'restarted\n'
fi
case "$1" in
    health) exit "${STUB_HEALTH_RC:-0}" ;;
    tcc-denied) exit 1 ;;
esac
SH
chmod +x "$FIXTURE/kanata-ctl"

cat > "$FIXTURE/pgrep" <<'SH'
#!/usr/bin/env bash
case "$*" in
    -f*) exit 0 ;;
    *) exit 1 ;;
esac
SH
chmod +x "$FIXTURE/pgrep"
: > "$FIXTURE/kanata.error.log"

run_reload() {
    : > "$CALLS"
    KANATA_CTL="$FIXTURE/kanata-ctl" HID_SETTLE_SECONDS=0 \
        bash "$SCRIPT" --force > "$FIXTURE/out" 2>&1
    wait_for_neutralize
}

run_check() {
    : > "$CALLS"
    KANATA_CTL="$FIXTURE/kanata-ctl" PGREP="$FIXTURE/pgrep" \
        KANATA_ERROR_LOG="$FIXTURE/kanata.error.log" HID_SETTLE_SECONDS=0 \
        bash "$SCRIPT" > "$FIXTURE/out" 2>&1
}

wait_for_neutralize() {
    for _ in $(seq 1 50); do
        if grep -q 'kanata-ctl neutralize' "$CALLS"; then
            return 0
        fi
        sleep 0.1
    done
    fail "neutralize was not called"
}

assert_order() {
    local first second
    first=$(grep -n "^kanata-ctl $1\$" "$CALLS" | cut -d: -f1 || true)
    second=$(grep -n "^kanata-ctl $2\$" "$CALLS" | cut -d: -f1 || true)
    [ -n "$first" ] || fail "missing 'kanata-ctl $1'"
    [ -n "$second" ] || fail "missing 'kanata-ctl $2'"
    [ "$first" -lt "$second" ] || fail "'$2' ran before '$1'"
}

# A forced reload always asks the helper to repair a vanished virtual
# keyboard before it restarts kanata.
STUB_ENSURE_RESTARTED=1 run_reload
assert_order ensure-hid restart
assert_order restart neutralize
grep -q 'VirtualHIDDevice-Daemon restarted' "$FIXTURE/out" \
    || fail "no warning after the helper restarted the virtual HID daemon"

# When the device is already present the helper stays quiet and the reload
# still restarts kanata.
STUB_ENSURE_RESTARTED=0 run_reload
assert_order ensure-hid restart
if grep -q 'VirtualHIDDevice-Daemon restarted' "$FIXTURE/out"; then
    fail "warned about a restart that did not happen"
fi

# A silently lost input grab (upstream #2094) must trigger the graceful
# restart even though the process and output sink are alive.
STUB_HEALTH_RC=1 run_check
wait_for_neutralize
grep -q 'input grab is missing' "$FIXTURE/out" || fail "no input-grab reason"
grep -qx 'kanata-ctl restart' "$CALLS" || fail "lost grab did not restart kanata"

# A healthy grab must not restart anything, so a wake has no dead-key window.
STUB_HEALTH_RC=0 run_check
grep -q 'Kanata is healthy' "$FIXTURE/out" || fail "no healthy message"
if grep -q 'kanata-ctl restart' "$CALLS"; then
    fail "healthy grab restarted kanata"
fi

echo "reload-kanata: all cases passed"
