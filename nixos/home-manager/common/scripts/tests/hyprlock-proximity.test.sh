#!/usr/bin/env bash
# Tests for hyprlock-proximity sensor gating. hyprctl is a stub and the sensor
# paths are temporary, so no live session is touched.
#
# Usage: bash nixos/home-manager/common/scripts/tests/hyprlock-proximity.test.sh
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROXIMITY="$SCRIPT_DIR/hyprlock-proximity"
WORK=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/hyprlock-proximity-test.XXXXXX")" && pwd -P)
SHIM="$WORK/shim"
LOG="$WORK/calls"
mkdir -p "$SHIM"
trap 'rm -rf "$WORK"' EXIT

cat > "$SHIM/hyprctl" <<'SH'
#!/usr/bin/env bash
printf 'hyprctl %s\n' "$*" >> "$LOG"
case "${1:-}" in
  locked) echo false ;;
  *) exit 1 ;;
esac
SH
chmod +x "$SHIM/hyprctl"
export PATH="$SHIM:$PATH"
export LOG

FAIL=0
check() {
  local label=$1
  shift
  if "$@"; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s\n' "$label"
    FAIL=1
  fi
}

# --- no sensors: exit cleanly without starting the poll loop ---------------
rm -f "$LOG"
export HYPRLOCK_PROXIMITY_SENSOR1="$WORK/no-sensor-1"
export HYPRLOCK_PROXIMITY_SENSOR2="$WORK/no-sensor-2"
export HYPRLOCK_PROXIMITY_MAX_ITERATIONS=1
export HYPRLOCK_PROXIMITY_POLL=0.01
if bash "$PROXIMITY" >/dev/null 2>&1; then
  check "no sensors exits cleanly" true
else
  check "no sensors exits cleanly" false
fi
check "no sensors never polls hyprctl" test ! -s "$LOG"

# --- one sensor present: the loop still runs -------------------------------
printf '1\n' > "$WORK/sensor-1"
: > "$LOG"
export HYPRLOCK_PROXIMITY_SENSOR1="$WORK/sensor-1"
if bash "$PROXIMITY" >/dev/null 2>&1; then
  check "sensor present exits cleanly after one iteration" true
else
  check "sensor present exits cleanly after one iteration" false
fi
check "sensor present polls hyprctl" grep -Fq 'hyprctl locked' "$LOG"

if [ "$FAIL" -ne 0 ]; then
  echo "hyprlock-proximity tests failed"
  exit 1
fi
echo "hyprlock-proximity tests passed"
