#!/usr/bin/env bash
# Tests for ../hypr-tmux-client.
#
# Contract under test:
#   - record stores the active window only when it is an ancestor of the tmux
#     client PID (the terminal the client attached from)
#   - focus uses a valid stored address/stable id, focusing that window (which
#     switches to its workspace)
#   - a stale/missing record falls back to the most recently focused Ghostty
#     window that owns the client's terminal app
#   - detach removes the stored entry
#
# hyprctl and ps are stubs, so no live compositor or terminal is involved.
# Usage: bash nixos/home-manager/common/scripts/tests/hypr-tmux-client.test.sh
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$SCRIPT_DIR/hypr-tmux-client"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/hypr-tmux-client-test.XXXXXX")
SHIM="$WORK/shim"
LOG="$WORK/calls"
RUN="$WORK/run"
mkdir -p "$SHIM" "$RUN"
export LOG HYPRLAND_INSTANCE_SIGNATURE=test XDG_RUNTIME_DIR="$RUN"

cat > "$SHIM/hyprctl" <<'SH'
#!/usr/bin/env bash
printf 'hyprctl %s\n' "$*" >> "$LOG"
case "$*" in
  "-j activewindow") cat "$FIXTURE_DIR/active" 2>/dev/null ;;
  "-j clients") cat "$FIXTURE_DIR/clients" 2>/dev/null ;;
esac
exit 0
SH

cat > "$SHIM/ps" <<'SH'
#!/usr/bin/env bash
# ps -o ppid= -p PID: the tmux client (120) came from the terminal (100).
pid=${!#}
case "$pid" in
  120) echo 100 ;;
  *) echo 1 ;;
esac
SH

chmod +x "$SHIM/hyprctl" "$SHIM/ps"

pass=0
fail=0
ok() { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() {
  printf 'FAIL  %s\n      %s\n' "$1" "$2"
  fail=$((fail + 1))
}

fixture() {
  FIXTURE_DIR="$WORK/$1"
  mkdir -p "$FIXTURE_DIR"
  : > "$FIXTURE_DIR/active"
  : > "$FIXTURE_DIR/clients"
  : > "$LOG"
  rm -rf "$RUN/hypr-tmux-clients"
}

run() {
  PATH="$SHIM:$PATH" FIXTURE_DIR="$FIXTURE_DIR" bash "$SCRIPT" "$@"
}

state_file="$RUN/hypr-tmux-clients/pts_9"

case_record() {
  echo "== record only the terminal the client attached from =="
  fixture record
  printf '{"address":"0xabc","stableId":"2a","pid":100}\n' > "$FIXTURE_DIR/active"
  run record /dev/pts/9 120
  [[ "$(cat "$state_file" 2>/dev/null)" == $'0xabc\t2a' ]] &&
    ok "stores the ancestor window" ||
    bad "stores the ancestor window" "got: $(cat "$state_file" 2>/dev/null)"

  fixture unrelated
  printf '{"address":"0x999","stableId":"99","pid":999}\n' > "$FIXTURE_DIR/active"
  run record /dev/pts/9 120
  [[ ! -e "$state_file" ]] &&
    ok "ignores a focused window unrelated to the client" ||
    bad "ignores a focused window unrelated to the client" "got: $(cat "$state_file" 2>/dev/null)"
}

case_focus_recorded() {
  echo "== focus uses the recorded window and switches to its workspace =="
  fixture recorded
  mkdir -p "$(dirname "$state_file")"
  printf '0xabc\t2a\n' > "$state_file"
  printf '[{"address":"0xabc","stableId":"2a","pid":100,"focusHistoryID":5}]\n' > "$FIXTURE_DIR/clients"
  run focus /dev/pts/9 120
  grep -q "address:0xabc" "$LOG" &&
    grep -q "tonumber('2a', 16)" "$LOG" &&
    ok "focuses address:0xabc with the stored stable id" ||
    bad "focuses address:0xabc with the stored stable id" "calls: $(tr '\n' ';' < "$LOG")"
}

case_focus_fallback() {
  echo "== stale/missing record falls back to the terminal app's newest window =="
  fixture stale
  mkdir -p "$(dirname "$state_file")"
  printf '0x999\t99\n' > "$state_file"
  printf '[{"address":"0xabc","stableId":"2a","pid":100,"focusHistoryID":5},{"address":"0xdef","stableId":"2b","pid":100,"focusHistoryID":0}]\n' > "$FIXTURE_DIR/clients"
  run focus /dev/pts/9 120
  grep -q "address:0xdef" "$LOG" &&
    ! grep -q "address:0x999" "$LOG" &&
    ok "ignores the stale address and picks the newest terminal window" ||
    bad "ignores the stale address and picks the newest terminal window" "calls: $(tr '\n' ';' < "$LOG")"

  fixture missing
  printf '[{"address":"0xabc","stableId":"2a","pid":100,"focusHistoryID":5},{"address":"0xdef","stableId":"2b","pid":100,"focusHistoryID":0}]\n' > "$FIXTURE_DIR/clients"
  run focus /dev/pts/9 120
  grep -q "address:0xdef" "$LOG" &&
    ok "works without a record (client attached before the hook)" ||
    bad "works without a record (client attached before the hook)" "calls: $(tr '\n' ';' < "$LOG")"
}

case_detach() {
  echo "== detach removes the recorded window =="
  fixture detach
  mkdir -p "$(dirname "$state_file")"
  printf '0xabc\t2a\n' > "$state_file"
  run detach /dev/pts/9
  [[ ! -e "$state_file" ]] &&
    ok "removes the state file" ||
    bad "removes the state file" "still exists: $(cat "$state_file" 2>/dev/null)"
}

case_record
case_focus_recorded
case_focus_fallback
case_detach

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then
  printf 'scratch kept for inspection: %s\n' "$WORK"
  exit 1
fi
rm -rf "$WORK"
