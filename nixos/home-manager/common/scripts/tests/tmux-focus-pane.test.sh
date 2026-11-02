#!/usr/bin/env bash
# Tests for ../tmux-focus-pane.
#
# Contract under test:
#   - never moves a client that is not attached to the pane's session (the
#     "switches the session, focuses the wrong window" bug); for an attached
#     session it only selects the window/pane and refreshes those clients
#   - a detached session moves the most recently active client, explicitly
#     (-c <tty>), and reports that same client
#   - the printed title is the target session's set-titles-string expanded for
#     the pane, which is what the window manager matches
#   - bad or unknown pane ids print nothing and do not touch tmux state
#
# tmux is a stub that records every call and serves canned output, so no live
# tmux server, terminal or Hammerspoon is involved. Fields are served one call
# at a time (the script cannot split tab-separated -F output: tmux rewrites
# tabs as "_" when the locale is unset, as in a launchd child).
#
# Usage: bash nixos/home-manager/common/scripts/tests/tmux-focus-pane.test.sh
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$SCRIPT_DIR/tmux-focus-pane"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tmux-focus-pane-test.XXXXXX")
SHIM="$WORK/shim"
LOG="$WORK/calls"
mkdir -p "$SHIM"

cat > "$SHIM/tmux" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LOG"
case "${1:-}" in
  list-clients)
    if [[ " $* " == *" -t "* ]]; then
      cat "${FIXTURE_DIR}/session_clients" 2>/dev/null
    else
      cat "${FIXTURE_DIR}/all_clients" 2>/dev/null
    fi
    ;;
  show)
    cat "${FIXTURE_DIR}/format" 2>/dev/null
    ;;
  display)
    last="${!#}"
    case "$last" in
      '#{session_name}') cat "${FIXTURE_DIR}/session" 2>/dev/null ;;
      '#{window_index}') cat "${FIXTURE_DIR}/window" 2>/dev/null ;;
      '#{client_pid}') cat "${FIXTURE_DIR}/pid" 2>/dev/null ;;
      *) cat "${FIXTURE_DIR}/title" 2>/dev/null ;;
    esac
    ;;
esac
exit 0
SH
chmod +x "$SHIM/tmux"

pass=0
fail=0
ok() { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() {
  printf 'FAIL  %s\n      %s\n' "$1" "$2"
  fail=$((fail + 1))
}

# fixture <name>: resets the per-case input files and call log.
fixture() {
  FIXTURE_DIR="$WORK/$1"
  mkdir -p "$FIXTURE_DIR"
  for f in session window title pid format session_clients all_clients; do
    : > "$FIXTURE_DIR/$f"
  done
  : > "$LOG"
}

# run [args...]: sets RUN_EXIT, RUN_OUT, RUN_ERR.
run() {
  ( PATH="$SHIM:$PATH" LOG="$LOG" FIXTURE_DIR="$FIXTURE_DIR" \
      bash "$SCRIPT" "$@" ) > "$WORK/out" 2> "$WORK/err"
  RUN_EXIT=$?
  RUN_OUT=$(cat "$WORK/out")
  RUN_ERR=$(cat "$WORK/err")
}

has() { grep -qxF -- "$1" "$LOG"; }
hasnt() { ! grep -qF -- "$1" "$LOG"; }

# --- attached session: select, never switch -----------------------------------
fixture attached
printf 'focus test\n' > "$FIXTURE_DIR/session"
printf '2\n' > "$FIXTURE_DIR/window"
printf '/dev/ttys047\n' > "$FIXTURE_DIR/session_clients"
printf '#{session_name}:#{window_index}\n' > "$FIXTURE_DIR/format"
printf 'focus test:2\n' > "$FIXTURE_DIR/title"
printf '4242\n' > "$FIXTURE_DIR/pid"
run %55
if [[ $RUN_EXIT -eq 0 && $RUN_OUT == $'title=focus test:2\nclient=/dev/ttys047 4242' ]]; then
  ok "attached: prints title and client"
else
  bad "attached: prints title and client" "exit=$RUN_EXIT out=[$RUN_OUT] err=[$RUN_ERR]"
fi
has "select-window -t focus test:2" && ok "attached: selects window" || bad "attached: selects window" "$(tr '\n' ';' < "$LOG")"
has "select-pane -t %55" && ok "attached: selects pane" || bad "attached: selects pane" "$(tr '\n' ';' < "$LOG")"
has "refresh-client -S -t /dev/ttys047" && ok "attached: refreshes its client" || bad "attached: refreshes its client" "$(tr '\n' ';' < "$LOG")"
hasnt "switch-client" && ok "attached: no client switched" || bad "attached: no client switched" "$(tr '\n' ';' < "$LOG")"
grep -qF -- "display -p -t %55 #{session_name}:#{window_index}" "$LOG" \
  && ok "attached: expands the session title format" \
  || bad "attached: expands the session title format" "$(tr '\n' ';' < "$LOG")"

# --- detached session: move the most recent client ---------------------------
fixture detached
printf 'focus-test\n' > "$FIXTURE_DIR/session"
printf '2\n' > "$FIXTURE_DIR/window"
printf '/dev/ttys039 100\n/dev/ttys047 200\n' > "$FIXTURE_DIR/all_clients"
printf '#{session_name}:#{window_index}\n' > "$FIXTURE_DIR/format"
printf 'focus-test:2\n' > "$FIXTURE_DIR/title"
printf '4242\n' > "$FIXTURE_DIR/pid"
run %55
if [[ $RUN_EXIT -eq 0 && $RUN_OUT == $'title=focus-test:2\nclient=/dev/ttys047 4242' ]]; then
  ok "detached: reports the moved client"
else
  bad "detached: reports the moved client" "exit=$RUN_EXIT out=[$RUN_OUT] err=[$RUN_ERR]"
fi
has "switch-client -c /dev/ttys047 -t focus-test" && ok "detached: switches the most recent client explicitly" \
  || bad "detached: switches the most recent client explicitly" "$(tr '\n' ';' < "$LOG")"
has "refresh-client -S -t /dev/ttys047" && ok "detached: refreshes the moved client" \
  || bad "detached: refreshes the moved client" "$(tr '\n' ';' < "$LOG")"

# --- no clients, unknown pane, bad pane --------------------------------------
fixture nobody
printf 'focus-test\n' > "$FIXTURE_DIR/session"
printf '2\n' > "$FIXTURE_DIR/window"
run %55
[[ $RUN_EXIT -eq 2 && -z $RUN_OUT ]] && ok "no clients: exits 2 silently" \
  || bad "no clients: exits 2 silently" "exit=$RUN_EXIT out=[$RUN_OUT] err=[$RUN_ERR]"
hasnt "select-window" && ok "no clients: does not select" || bad "no clients: does not select" "$(tr '\n' ';' < "$LOG")"

fixture unknown
run %55
[[ $RUN_EXIT -eq 1 && -z $RUN_OUT ]] && ok "unknown pane: exits 1" \
  || bad "unknown pane: exits 1" "exit=$RUN_EXIT out=[$RUN_OUT] err=[$RUN_ERR]"

fixture badid
run '%1;touch /tmp/x'
[[ $RUN_EXIT -eq 1 && -z $RUN_OUT ]] && ok "bad pane id: rejected" \
  || bad "bad pane id: rejected" "exit=$RUN_EXIT out=[$RUN_OUT] err=[$RUN_ERR]"
[[ ! -s $LOG ]] && ok "bad pane id: tmux untouched" || bad "bad pane id: tmux untouched" "$(tr '\n' ';' < "$LOG")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
