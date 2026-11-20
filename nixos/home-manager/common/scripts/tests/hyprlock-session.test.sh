#!/usr/bin/env bash
# Regression tests for the hyprlock session helpers.
#
# A leaked hyprlock process used to:
#   - make hyprlock-proximity inject Return every 10 s into the focused app
#   - make hyprlock-absence believe the session was locked, disabling absence lock
#
# Both services must key off Hyprland's real session-lock state
# (`hyprctl locked`), never off process existence.
#
# hyprctl, hyprlock, wtype, systemctl and hyprlock-session are stubs. The
# process name used for stale-locker tests is "hl-test", so a real hyprlock on
# the developer machine is never touched.
#
# Usage: bash nixos/home-manager/common/scripts/tests/hyprlock-session.test.sh
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/hyprlock-session-test.XXXXXX")" && pwd -P)
cleanup() {
  if [ -n "${WATCH_PID:-}" ]; then
    kill "$WATCH_PID" 2>/dev/null || true
    wait "$WATCH_PID" 2>/dev/null || true
  fi
  reap_stale
  rm -rf "$WORK"
}
trap cleanup EXIT

SHIM="$WORK/shim"
STATE="$WORK/state"
LOG="$WORK/calls"
RUN="$WORK/run"
mkdir -p "$SHIM" "$STATE" "$RUN"

export XDG_RUNTIME_DIR="$RUN"
export STATE LOG
export HYPRLAND_INSTANCE_SIGNATURE=test-sig
export HYPRLOCK_BIN="$SHIM/hyprlock"
export HYPRLOCK_PROCESS_NAME=hl-test
export PATH="$SHIM:$PATH"

cat > "$SHIM/hyprctl" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  locked)
    [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || { echo "no signature" >&2; exit 1; }
    cat "$STATE/locked"
    ;;
  instances)
    printf 'instance test-sig:\n\ttime: 1\n\tpid: 1\n\twl socket: wayland-test\n\n'
    ;;
  *)
    echo "unexpected hyprctl: $*" >&2
    exit 1
    ;;
esac
SH

cat > "$SHIM/hyprlock" <<'SH'
#!/usr/bin/env bash
printf 'hyprlock\n' >> "$LOG"
sleep 0.05
printf 'true\n' > "$STATE/locked"
SH

cat > "$SHIM/wtype" <<'SH'
#!/usr/bin/env bash
printf 'wtype %s\n' "$*" >> "$LOG"
SH

cat > "$SHIM/systemctl" <<'SH'
#!/usr/bin/env bash
# hypr-idle-inhibit.service is inactive in tests
exit 1
SH

cat > "$SHIM/hyprlock-session" <<'SH'
#!/usr/bin/env bash
printf 'hyprlock-session %s\n' "$*" >> "$LOG"
printf 'true\n' > "$STATE/locked"
SH
chmod +x "$SHIM"/*

pass=0
fail=0
ok() {
  printf 'PASS  %s\n' "$1"
  pass=$((pass + 1))
}
no() {
  printf 'FAIL  %s\n' "$1"
  [ -s "$LOG" ] && printf '      calls: %s\n' "$(tr '\n' ';' < "$LOG")"
  fail=$((fail + 1))
}

reset_state() {
  : > "$LOG"
  printf 'false\n' > "$STATE/locked"
  printf '0\n' > "$STATE/sensor1"
  printf '0\n' > "$STATE/sensor2"
  rm -f "$STATE/trigger"
}

set_locked() { printf '%s\n' "$1" > "$STATE/locked"; }
count_log() { grep -c -- "$1" "$LOG" 2>/dev/null || true; }

start_stale() {
  # A bash symlink named hl-test gives the process that comm name, so pgrep
  # and pkill see it like the real hyprlock binary.
  ln -sf "$(command -v bash)" "$WORK/hl-test"
  "$WORK/hl-test" -c 'while :; do sleep 1; done' &
  STALE_PID=$!
  for _ in $(seq 1 20); do
    pgrep -x hl-test >/dev/null && return 0
    sleep 0.05
  done
  return 1
}

reap_stale() {
  [ -n "${STALE_PID:-}" ] || return 0
  kill "$STALE_PID" 2>/dev/null || true
  wait "$STALE_PID" 2>/dev/null || true
  unset STALE_PID
}

run_proximity() { # run_proximity <iterations>
  HYPRLOCK_PROXIMITY_SENSOR1="$STATE/sensor1" \
    HYPRLOCK_PROXIMITY_SENSOR2="$STATE/sensor2" \
    HYPRLOCK_PROXIMITY_TRIGGER_FILE="$STATE/trigger" \
    HYPRLOCK_PROXIMITY_POLL=0 \
    HYPRLOCK_PROXIMITY_MAX_ITERATIONS="$1" \
    "$SCRIPT_DIR/hyprlock-proximity"
}

run_absence() { # run_absence <delay> <iterations>
  HYPRLOCK_ABSENCE_SENSOR1="$STATE/sensor1" \
    HYPRLOCK_ABSENCE_SENSOR2="$STATE/sensor2" \
    HYPRLOCK_ABSENCE_DELAY="$1" \
    HYPRLOCK_ABSENCE_POLL=0.1 \
    HYPRLOCK_ABSENCE_MAX_ITERATIONS="$2" \
    "$SCRIPT_DIR/hyprlock-absence"
}

echo "== hyprlock-session =="

reset_state
set_locked true
if "$SCRIPT_DIR/hyprlock-session" start && [ ! -s "$LOG" ]; then
  ok "start does nothing when the compositor reports the session locked"
else
  no "start does nothing when the compositor reports the session locked"
fi

reset_state
if "$SCRIPT_DIR/hyprlock-session" start && grep -qx 'hyprlock' "$LOG" && [ "$(cat "$STATE/locked")" = true ]; then
  ok "start launches hyprlock when unlocked and waits for the lock"
else
  no "start launches hyprlock when unlocked and waits for the lock"
fi

reset_state
if start_stale; then
  "$SCRIPT_DIR/hyprlock-session" start
  rc=$?
  reap_stale
  if [ "$rc" -eq 0 ] && ! pgrep -x hl-test >/dev/null && [ "$(count_log '^hyprlock$')" -eq 1 ]; then
    ok "start reaps a stale hyprlock when the session is unlocked"
  else
    no "start reaps a stale hyprlock when the session is unlocked"
  fi
else
  no "start reaps a stale hyprlock when the session is unlocked (could not start fixture)"
fi

reset_state
set_locked true
if start_stale; then
  (sleep 0.2; set_locked false) &
  WATCH_PID=$!
  "$SCRIPT_DIR/hyprlock-session" restart
  rc=$?
  kill "$WATCH_PID" 2>/dev/null || true
  wait "$WATCH_PID" 2>/dev/null || true
  unset WATCH_PID
  reap_stale
  if [ "$rc" -eq 0 ] && [ "$(count_log '^hyprlock$')" -eq 1 ] && [ "$(cat "$STATE/locked")" = true ]; then
    ok "restart replaces a wedged locked instance"
  else
    no "restart replaces a wedged locked instance"
  fi
else
  no "restart replaces a wedged locked instance (could not start fixture)"
fi

reset_state
if (
  unset HYPRLAND_INSTANCE_SIGNATURE
  "$SCRIPT_DIR/hyprlock-session" start
); then
  if grep -qx 'hyprlock' "$LOG"; then
    ok "start works from a TTY without a Hyprland environment"
  else
    no "start works from a TTY without a Hyprland environment"
  fi
else
  no "start works from a TTY without a Hyprland environment"
fi
export HYPRLAND_INSTANCE_SIGNATURE=test-sig

echo "== hyprlock-proximity =="

reset_state
printf '1\n' > "$STATE/sensor1"
start_stale
rc=0
run_proximity 5 || rc=$?
reap_stale
if [ "$rc" -eq 0 ] && [ "$(count_log '^wtype ')" -eq 0 ]; then
  ok "unlocked session never injects Return, even with a leaked process"
else
  no "unlocked session never injects Return, even with a leaked process"
fi

reset_state
set_locked true
printf '1\n' > "$STATE/sensor1"
rc=0
run_proximity 10 || rc=$?
if [ "$rc" -eq 0 ] && [ "$(count_log '^wtype ')" -eq 1 ]; then
  ok "locked session wakes once and does not re-send Return periodically"
else
  no "locked session wakes once and does not re-send Return periodically"
fi

reset_state
set_locked true
touch "$STATE/trigger"
rc=0
run_proximity 3 || rc=$?
if [ "$rc" -eq 0 ] && [ "$(count_log '^wtype ')" -eq 1 ] && [ ! -e "$STATE/trigger" ]; then
  ok "manual scan-face trigger wakes while locked"
else
  no "manual scan-face trigger wakes while locked"
fi

reset_state
touch "$STATE/trigger"
rc=0
run_proximity 3 || rc=$?
if [ "$rc" -eq 0 ] && [ "$(count_log '^wtype ')" -eq 0 ] && [ ! -e "$STATE/trigger" ]; then
  ok "manual scan-face trigger is discarded while unlocked"
else
  no "manual scan-face trigger is discarded while unlocked"
fi

echo "== hyprlock-absence =="

reset_state
set_locked true
rc=0
run_absence 0 5 || rc=$?
if [ "$rc" -eq 0 ] && [ "$(count_log '^hyprlock-session ')" -eq 0 ]; then
  ok "absence lock does nothing when the compositor reports locked"
else
  no "absence lock does nothing when the compositor reports locked"
fi

reset_state
rc=0
run_absence 1 30 || rc=$?
if [ "$rc" -eq 0 ] && [ "$(count_log '^hyprlock-session start')" -eq 1 ]; then
  ok "absence lock starts the locker after the delay"
else
  no "absence lock starts the locker after the delay"
fi

reset_state
start_stale
rc=0
run_absence 0 5 || rc=$?
reap_stale
if [ "$rc" -eq 0 ] && [ "$(count_log '^hyprlock-session start')" -eq 1 ]; then
  ok "a leaked process does not suppress absence lock"
else
  no "a leaked process does not suppress absence lock"
fi

reset_state
printf '1\n' > "$STATE/sensor1"
rc=0
run_absence 0 5 || rc=$?
if [ "$rc" -eq 0 ] && [ "$(count_log '^hyprlock-session ')" -eq 0 ]; then
  ok "presence prevents absence lock"
else
  no "presence prevents absence lock"
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
