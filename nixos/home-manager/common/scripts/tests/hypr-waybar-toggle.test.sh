#!/usr/bin/env bash
# Tests for hypr-waybar-toggle spawning bars outside the caller's service
# cgroup. hyprctl/waybar/nohup/pkill/killall/pgrep are stubs and the runtime
# and Hyprland signature directories are temporary, so no live session is
# touched.
#
# Usage: bash nixos/home-manager/common/scripts/tests/hypr-waybar-toggle.test.sh
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TOGGLE="$SCRIPT_DIR/hypr-waybar-toggle"
WORK=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/hypr-waybar-toggle-test.XXXXXX")" && pwd -P)
SHIM="$WORK/shim"
RUN="$WORK/run"
SIG="$WORK/hypr"
LOG="$WORK/calls"
mkdir -p "$SHIM" "$RUN" "$SIG/test-instance" "$WORK/home"
trap 'rm -rf "$WORK"' EXIT

export HOME="$WORK/home"
export XDG_RUNTIME_DIR="$RUN"
export HYPR_SIG_DIR="$SIG"
export LOG
unset HYPRLAND_INSTANCE_SIGNATURE

cat > "$SHIM/hyprctl" <<'SH'
#!/usr/bin/env bash
printf 'hyprctl %s\n' "$*" >> "$LOG"
case "${1:-}" in
  instances) printf '[{"instance":"test-instance","wl_socket":"wayland-test"}]\n' ;;
  eval)
    # Only the live instance resolved from HYPR_SIG_DIR may be used.
    [ "${HYPRLAND_INSTANCE_SIGNATURE:-}" = "test-instance" ] || exit 1
    [ -n "${HYPRCTL_EVAL_FAIL:-}" ] && exit 1
    echo ok
    ;;
  *) exit 1 ;;
esac
SH

cat > "$SHIM/waybar" <<'SH'
#!/usr/bin/env bash
printf 'waybar %s\n' "$*" >> "$LOG"
SH

cat > "$SHIM/nohup" <<'SH'
#!/usr/bin/env bash
printf 'nohup %s\n' "$*" >> "$LOG"
SH

cat > "$SHIM/pkill" <<'SH'
#!/usr/bin/env bash
printf 'pkill %s\n' "$*" >> "$LOG"
SH

cat > "$SHIM/killall" <<'SH'
#!/usr/bin/env bash
printf 'killall %s\n' "$*" >> "$LOG"
SH

cat > "$SHIM/pgrep" <<'SH'
#!/usr/bin/env bash
printf 'pgrep %s\n' "$*" >> "$LOG"
exit 1
SH

chmod +x "$SHIM"/*
export PATH="$SHIM:$PATH"

FAIL=0
check_contains() {
  local label=$1 needle=$2
  if grep -Fq "$needle" "$LOG"; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s (missing: %s)\n' "$label" "$needle"
    FAIL=1
  fi
}

check_count() {
  local label=$1 want=$2 pattern=$3 got
  got=$(grep -cE "$pattern" "$LOG" 2>/dev/null || true)
  if [ "$want" = "$got" ]; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$label" "$want" "$got"
    FAIL=1
  fi
}

check_not_contains() {
  local label=$1 needle=$2
  if grep -Fq "$needle" "$LOG"; then
    printf 'FAIL %s (unexpected: %s)\n' "$label" "$needle"
    FAIL=1
  else
    printf 'PASS %s\n' "$label"
  fi
}

run() { bash "$TOGGLE" "$@"; }

# --- bars are spawned by Hyprland, not inside the calling service cgroup -----
: > "$LOG"
run on
check_count "three bars via Hyprland" 3 '^hyprctl eval hl\.exec_cmd\(\[\['
check_contains "top bar command" 'waybar -c '
check_contains "bottom bar config" 'config-hypr-bottom'
check_contains "external bar config" 'config-hypr-external'
check_not_contains "no direct nohup fallback" 'nohup '
check_contains "quickshell is stopped first" 'pkill -f ^([^ ]*/)?quickshell -c shell'

# --- a stale inherited signature is replaced with the live one --------------
: > "$LOG"
HYPRLAND_INSTANCE_SIGNATURE=stale run on
check_count "stale signature still uses Hyprland" 3 '^hyprctl eval hl\.exec_cmd\(\[\['
check_not_contains "stale signature does not fall back" 'nohup '

# --- no Hyprland: fall back to direct spawn (still three bars) --------------
: > "$LOG"
HYPRCTL_EVAL_FAIL=1 run on
sleep 0.2
check_count "fallback starts three bars" 3 '^nohup waybar '
check_contains "fallback keeps the bottom config" 'config-hypr-bottom'

# --- off stops the bars ------------------------------------------------
: > "$LOG"
run off
check_contains "off kills hypr Waybars" 'pkill -f waybar -c .*config-hypr'
check_not_contains "off starts nothing" 'hyprctl eval'

if [ "$FAIL" -ne 0 ]; then
  echo "hypr-waybar-toggle tests failed"
  exit 1
fi
echo "hypr-waybar-toggle tests passed"
