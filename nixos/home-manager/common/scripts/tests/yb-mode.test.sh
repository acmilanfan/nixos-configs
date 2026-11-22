#!/usr/bin/env bash
# Tests for the Yoga Book dock-state watcher / mode selector.
#
# Hyprland, swaybg, wvkbd, yb-touchpad, systemctl and pkill are stubs. The
# sysfs keyboard_position file and runtime dirs are temporary, so the test
# never touches the live session.
#
# Usage: bash nixos/home-manager/common/scripts/tests/yb-mode.test.sh
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
YB_MODE="$SCRIPT_DIR/yb-mode"
WORK=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/yb-mode-test.XXXXXX")" && pwd -P)
SHIM="$WORK/shim"
STATE="$WORK/state"
LOG="$WORK/calls"
RUN="$WORK/run"
mkdir -p "$SHIM" "$STATE" "$RUN"

cleanup() {
  local pid file
  for file in "$RUN/yb-touchpad/pid" "$RUN/wvkbd.pid"; do
    [ -r "$file" ] || continue
    pid=$(cat "$file" 2>/dev/null || true)
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  done
  rm -rf "$WORK"
}
trap cleanup EXIT

export XDG_RUNTIME_DIR="$RUN"
export YB_MODE_RUNTIME_DIR="$RUN"
export YB_MODE_SYSFS_GLOB="$WORK/wmi/*/keyboard_position"
export YB_MODE_WVKBD="$SHIM/wvkbd-mobintl"
export STATE LOG
export PATH="$SHIM:$PATH"

mkdir -p "$WORK/wmi/dev1"
SIGNAL="$WORK/wmi/dev1/keyboard_position"

cat > "$SHIM/hyprctl" <<'SH'
#!/usr/bin/env bash
printf 'hyprctl %s\n' "$*" >> "$LOG"
case "${1:-}" in
  instances) echo '[{"instance":"test","wl_socket":"wayland-test"}]' ;;
  monitors) cat "$STATE/monitors.json" ;;
  workspaces) cat "$STATE/workspaces.json" ;;
  clients) echo '[]' ;;
  eval|dispatch) echo 'ok' ;;
  *) echo "unexpected hyprctl: $*" >&2; exit 1 ;;
esac
SH

cat > "$SHIM/swaybg" <<'SH'
#!/usr/bin/env bash
printf 'swaybg %s\n' "$*" >> "$LOG"
sleep 0.3
SH

cat > "$SHIM/wvkbd-mobintl" <<'SH'
#!/usr/bin/env bash
printf 'wvkbd-mobintl %s\n' "$*" >> "$LOG"
sleep 0.3
SH

cat > "$SHIM/yb-touchpad" <<'SH'
#!/usr/bin/env bash
printf 'yb-touchpad %s\n' "$*" >> "$LOG"
if [ "${1:-}" = window ]; then
  mkdir -p "$XDG_RUNTIME_DIR/yb-touchpad"
  printf '%s\n' "$$" > "$XDG_RUNTIME_DIR/yb-touchpad/pid"
  trap 'exit 0' TERM
  while :; do sleep 0.1; done
fi
SH

cat > "$SHIM/systemctl" <<'SH'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$LOG"
SH

cat > "$SHIM/pkill" <<'SH'
#!/usr/bin/env bash
printf 'pkill %s\n' "$*" >> "$LOG"
SH

cat > "$SHIM/waybar" <<'SH'
#!/usr/bin/env bash
printf 'waybar %s\n' "$*" >> "$LOG"
sleep 0.3
SH

cat > "$SHIM/pgrep" <<'SH'
#!/usr/bin/env bash
printf 'pgrep %s\n' "$*" >> "$LOG"
if [[ "$1" == -f && "$2" == *quickshell* && -n "${YB_TEST_QS:-}" ]]; then
  exit 0
fi
exit 1
SH

chmod +x "$SHIM"/*

cat > "$STATE/monitors.json" <<'JSON'
[
  {"name":"eDP-1","x":0,"y":0,"width":2880,"height":1800,"scale":1.6,"focused":true},
  {"name":"eDP-2","x":0,"y":1130,"width":2880,"height":1800,"scale":1.6,"focused":false}
]
JSON

cat > "$STATE/workspaces.json" <<'JSON'
[
  {"id":1,"monitor":"eDP-2","windows":1},
  {"id":11,"monitor":"eDP-1","windows":1}
]
JSON

FAIL=0
check_eq() {
  local label=$1 want=$2 got=$3
  if [ "$want" = "$got" ]; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$label" "$want" "$got"
    FAIL=1
  fi
}

check_contains() {
  local label=$1 needle=$2
  if grep -Fq "$needle" "$LOG"; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s (missing: %s)\n' "$label" "$needle"
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

set_signal() { printf '%s\n' "$1" > "$SIGNAL"; }
status() { "$YB_MODE" status; }
daemon_once() { YB_MODE_ONCE=1 "$YB_MODE" daemon >/dev/null; }

# --- signal mapping ---------------------------------------------------------
set_signal 2
check_eq "lower dock status" "signal=docked-lower mode=laptop override=auto" "$(status)"
set_signal 1
check_eq "upper dock status" "signal=docked-upper mode=laptop override=auto" "$(status)"
set_signal 0
check_eq "detached status" "signal=detached mode=dual override=auto" "$(status)"

rm -f "$SIGNAL"
check_eq "missing signal is unknown" "signal=unknown mode=dual override=auto" "$(status)"
printf '9\n' > "$SIGNAL"
check_eq "invalid signal is unknown" "signal=unknown mode=dual override=auto" "$(status)"

# --- manual override and auto ---------------------------------------------
set_signal 2
"$YB_MODE" dual >/dev/null
check_eq "manual dual override" "signal=docked-lower mode=dual override=dual" "$(status)"
"$YB_MODE" auto >/dev/null
check_eq "auto returns to laptop" "signal=docked-lower mode=laptop override=auto" "$(status)"
"$YB_MODE" virtual-laptop >/dev/null
check_eq "manual virtual-laptop override" "signal=docked-lower mode=virtual-laptop override=virtual-laptop" "$(status)"
"$YB_MODE" auto >/dev/null

# --- daemon state files ----------------------------------------------------
set_signal 2
daemon_once
check_eq "daemon writes signal" "2" "$(cat "$YB_MODE_RUNTIME_DIR/signal")"
check_eq "daemon writes mode" "laptop" "$(cat "$YB_MODE_RUNTIME_DIR/mode")"

# A manual override survives the first daemon iteration...
set_signal 2
"$YB_MODE" dual >/dev/null
daemon_once
check_eq "manual survives first daemon run" "signal=docked-lower mode=dual override=dual" "$(status)"

# ...but a real dock change clears it.
set_signal 1
daemon_once
check_eq "dock change clears override" "signal=docked-upper mode=laptop override=auto" "$(status)"

# --- mode actions ----------------------------------------------------------
: > "$LOG"
set_signal 2
"$YB_MODE" laptop >/dev/null
check_contains "laptop sets top-only rules" 'for i=1,20 do hl.workspace_rule'
check_contains "laptop blacks eDP-2" 'swaybg -o eDP-2 -c #000000'
check_contains "laptop locks rotation" 'systemctl --user stop hypr-iio-rotate.service'
check_contains "laptop hides bottom bar" 'pkill -f waybar -c .*config-hypr-bottom'
check_contains "laptop puts pad on upper free half" 'yb-touchpad window 900 1366 --size 1760x433'
check_not_contains "laptop does not launch wvkbd" 'wvkbd-mobintl -H'

: > "$LOG"
set_signal 1
"$YB_MODE" laptop >/dev/null
check_contains "laptop puts pad on lower free half" 'yb-touchpad window 900 2018 --size 1760x433'

: > "$LOG"
"$YB_MODE" virtual-laptop >/dev/null
check_contains "virtual-laptop launches keyboard" 'wvkbd-mobintl -H 652 -L 652'
check_contains "virtual-laptop locks rotation" 'systemctl --user stop hypr-iio-rotate.service'
check_contains "virtual-laptop hides bottom bar" 'pkill -f waybar -c .*config-hypr-bottom'
check_contains "virtual-laptop puts pad below keyboard" 'yb-touchpad window 900 2018 --size 1760x433'

: > "$LOG"
"$YB_MODE" dual >/dev/null
check_contains "dual restores bottom rules" 'for i=1,10 do hl.workspace_rule'
check_contains "dual restores top rules" 'for i=11,20 do hl.workspace_rule'
check_contains "dual releases rotation" 'systemctl --user start hypr-iio-rotate.service'
check_contains "dual removes black layer" 'pkill -f swaybg -o eDP-2'
check_contains "dual restores bottom bar" 'config-hypr-bottom'
check_not_contains "dual does not launch wvkbd" 'wvkbd-mobintl -H'

: > "$LOG"
YB_TEST_QS=1 "$YB_MODE" dual >/dev/null
check_not_contains "dual leaves the bottom bar to the Quickshell shell" 'config-hypr-bottom'

# --- SUPER+M cycle ---------------------------------------------------------
set_signal 0
"$YB_MODE" auto >/dev/null
"$YB_MODE" cycle >/dev/null
check_eq "cycle detached to virtual" "signal=detached mode=virtual-laptop override=virtual-laptop" "$(status)"
"$YB_MODE" cycle >/dev/null
check_eq "cycle back to dual" "signal=detached mode=dual override=dual" "$(status)"
set_signal 2
before=$(status)
"$YB_MODE" cycle >/dev/null
check_eq "cycle ignored while docked" "$before" "$(status)"

# --- invalid mode is rejected ---------------------------------------------
set_signal 2
before=$(status)
if "$YB_MODE" nonsense >/dev/null 2>&1; then
  printf 'FAIL invalid mode should fail\n'
  FAIL=1
else
  printf 'PASS invalid mode fails\n'
fi
check_eq "invalid mode leaves state alone" "$before" "$(status)"

if [ "$FAIL" -ne 0 ]; then
  echo "yb-mode tests failed"
  exit 1
fi
echo "yb-mode tests passed"
