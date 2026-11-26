#!/usr/bin/env bash
# Tests for ../tmux-focus-pane.
#
# Contract under test:
#   - never moves a client that is not attached to the pane's session (the
#     "switches the session, focuses the wrong window" bug); for an attached
#     session it only selects the window/pane and refreshes those clients
#   - a detached session moves the most recently active client, explicitly
#     (-c <tty>), and reports that same client
#   - a retry (--source-title) moves the client currently showing the caller's
#     window title when the target session's attached clients are hidden, so
#     the caller gets a visible window to raise
#   - a retry never moves a client when the source title matches no client, or
#     when that client is already attached to the target session
#   - --source-title can repeat: the client showing the earliest listed title
#     is moved; titles no client shows (plain-shell windows) are skipped
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
      *)
        # Per-client title for --source-title, keyed by tty. The target pane
        # keeps the single target `title` fixture.
        tgt=""
        prev=""
        for a in "$@"; do
          [[ $prev == -t ]] && tgt=$a
          prev=$a
        done
        found=""
        while IFS='|' read -r tty t; do
          if [[ $tty == "$tgt" ]]; then found=$t; break; fi
        done < "${FIXTURE_DIR}/client_titles" 2>/dev/null
        if [[ -n $found ]]; then
          printf '%s\n' "$found"
        else
          cat "${FIXTURE_DIR}/title" 2>/dev/null
        fi
        ;;
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
  for f in session window title pid format session_clients all_clients client_titles; do
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

# --- retry: move the caller's client when the attached one is hidden ---------
fixture retry
printf 'focus-test\n' > "$FIXTURE_DIR/session"
printf '2\n' > "$FIXTURE_DIR/window"
printf '/dev/ttys047\n' > "$FIXTURE_DIR/session_clients"
printf '/dev/ttys039 100\n/dev/ttys047 200\n' > "$FIXTURE_DIR/all_clients"
printf '#{session_name}:#{window_index}\n' > "$FIXTURE_DIR/format"
printf 'focus-test:2\n' > "$FIXTURE_DIR/title"
printf '4242\n' > "$FIXTURE_DIR/pid"
printf '/dev/ttys039|wd-backend:7\n/dev/ttys047|focus-test:2\n' > "$FIXTURE_DIR/client_titles"
run --source-title wd-backend:7 %55
if [[ $RUN_EXIT -eq 0 && $RUN_OUT == $'title=focus-test:2\nclient=/dev/ttys039 4242\nclient=/dev/ttys047 4242' ]]; then
  ok "retry: moves the source client and reports it first"
else
  bad "retry: moves the source client and reports it first" "exit=$RUN_EXIT out=[$RUN_OUT] err=[$RUN_ERR]"
fi
has "switch-client -c /dev/ttys039 -t focus-test" && ok "retry: switches the source client explicitly" \
  || bad "retry: switches the source client explicitly" "$(tr '\n' ';' < "$LOG")"
has "refresh-client -S -t /dev/ttys039" && ok "retry: refreshes the source client" \
  || bad "retry: refreshes the source client" "$(tr '\n' ';' < "$LOG")"
has "refresh-client -S -t /dev/ttys047" && ok "retry: still refreshes the attached client" \
  || bad "retry: still refreshes the attached client" "$(tr '\n' ';' < "$LOG")"
has "select-window -t focus-test:2" && ok "retry: selects the window" \
  || bad "retry: selects the window" "$(tr '\n' ';' < "$LOG")"
has "select-pane -t %55" && ok "retry: selects the pane" \
  || bad "retry: selects the pane" "$(tr '\n' ';' < "$LOG")"

# --- retry: no matching source title leaves clients alone --------------------
fixture retry-nomatch
printf 'focus-test\n' > "$FIXTURE_DIR/session"
printf '2\n' > "$FIXTURE_DIR/window"
printf '/dev/ttys047\n' > "$FIXTURE_DIR/session_clients"
printf '/dev/ttys039 100\n/dev/ttys047 200\n' > "$FIXTURE_DIR/all_clients"
printf '#{session_name}:#{window_index}\n' > "$FIXTURE_DIR/format"
printf 'focus-test:2\n' > "$FIXTURE_DIR/title"
printf '4242\n' > "$FIXTURE_DIR/pid"
printf '/dev/ttys039|wd-backend:7\n/dev/ttys047|focus-test:2\n' > "$FIXTURE_DIR/client_titles"
run --source-title not-a-tmux-title %55
if [[ $RUN_EXIT -eq 0 && $RUN_OUT == $'title=focus-test:2\nclient=/dev/ttys047 4242' ]]; then
  ok "retry without a match: reports the attached client only"
else
  bad "retry without a match: reports the attached client only" "exit=$RUN_EXIT out=[$RUN_OUT] err=[$RUN_ERR]"
fi
hasnt "switch-client" && ok "retry without a match: no client switched" \
  || bad "retry without a match: no client switched" "$(tr '\n' ';' < "$LOG")"

# --- retry: do not move a client already attached to the target -------------
fixture retry-attached
printf 'focus-test\n' > "$FIXTURE_DIR/session"
printf '2\n' > "$FIXTURE_DIR/window"
printf '/dev/ttys047\n' > "$FIXTURE_DIR/session_clients"
printf '/dev/ttys047 200\n' > "$FIXTURE_DIR/all_clients"
printf '#{session_name}:#{window_index}\n' > "$FIXTURE_DIR/format"
printf 'focus-test:2\n' > "$FIXTURE_DIR/title"
printf '4242\n' > "$FIXTURE_DIR/pid"
printf '/dev/ttys047|focus-test:2\n' > "$FIXTURE_DIR/client_titles"
run --source-title focus-test:2 %55
if [[ $RUN_EXIT -eq 0 && $RUN_OUT == $'title=focus-test:2\nclient=/dev/ttys047 4242' ]]; then
  ok "retry with an attached source: reports the attached client only"
else
  bad "retry with an attached source: reports the attached client only" "exit=$RUN_EXIT out=[$RUN_OUT] err=[$RUN_ERR]"
fi
hasnt "switch-client" && ok "retry with an attached source: no client switched" \
  || bad "retry with an attached source: no client switched" "$(tr '\n' ';' < "$LOG")"

# --- retry: several source titles, the first tmux one wins -------------------
# The caller lists every terminal it can see, best first; the first is often a
# plain-shell window that no tmux client shows. It must be skipped, and an
# earlier title must win over a more recently active client.
fixture retry-multi
printf 'focus-test\n' > "$FIXTURE_DIR/session"
printf '2\n' > "$FIXTURE_DIR/window"
printf '/dev/ttys047\n' > "$FIXTURE_DIR/session_clients"
printf '/dev/ttys039 100\n/dev/ttys040 300\n/dev/ttys047 200\n' > "$FIXTURE_DIR/all_clients"
printf '#{session_name}:#{window_index}\n' > "$FIXTURE_DIR/format"
printf 'focus-test:2\n' > "$FIXTURE_DIR/title"
printf '4242\n' > "$FIXTURE_DIR/pid"
printf '/dev/ttys039|wd-backend:7\n/dev/ttys040|notes:1\n/dev/ttys047|focus-test:2\n' > "$FIXTURE_DIR/client_titles"
run --source-title '~' --source-title wd-backend:7 --source-title notes:1 %55
if [[ $RUN_EXIT -eq 0 && $RUN_OUT == $'title=focus-test:2\nclient=/dev/ttys039 4242\nclient=/dev/ttys047 4242' ]]; then
  ok "retry with several titles: moves the first tmux one"
else
  bad "retry with several titles: moves the first tmux one" "exit=$RUN_EXIT out=[$RUN_OUT] err=[$RUN_ERR]"
fi
has "switch-client -c /dev/ttys039 -t focus-test" && ok "retry with several titles: switches that client" \
  || bad "retry with several titles: switches that client" "$(tr '\n' ';' < "$LOG")"
hasnt "switch-client -c /dev/ttys040" && ok "retry with several titles: leaves the later match alone" \
  || bad "retry with several titles: leaves the later match alone" "$(tr '\n' ';' < "$LOG")"

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
