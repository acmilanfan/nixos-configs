#!/usr/bin/env bash
# Tests for ../tmux-agent-switcher: shared fzf theme and focus dispatch.
#
# Contract under test:
#   - the shared ~/.config/fzf/fzfrc is used on both platforms
#   - an inherited FZF_DEFAULT_OPTS is cleared when the rc exists
#   - a missing rc leaves inherited options alone and clears a stale file path
#   - fzf still gets the tmux popup args and the agent rows
#   - no agents or a cancelled fzf performs no focus action
#   - macOS forwards the %25-escaped pane id to Hammerspoon
#
# Usage: bash nixos/home-manager/common/scripts/tests/tmux-agent-switcher.test.sh
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$SCRIPT_DIR/tmux-agent-switcher"
REPO_ROOT=$(cd "$SCRIPT_DIR/../../../.." && pwd)
FZFRC_SRC="$REPO_ROOT/dotfiles/fzf/fzfrc"

if [ ! -r "$FZFRC_SRC" ]; then
  printf 'missing %s\n' "$FZFRC_SRC" >&2
  exit 1
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tmux-agent-switcher-test.XXXXXX")
SHIM="$WORK/shim"
HOME_DIR="$WORK/home"
FZFRC="$HOME_DIR/.config/fzf/fzfrc"
FZF_LOG="$WORK/fzf.log"
TMUX_LOG="$WORK/tmux.log"
HYPR_LOG="$WORK/hypr.log"
OPEN_LOG="$WORK/open.log"
mkdir -p "$SHIM" "$(dirname "$FZFRC")"
cp "$FZFRC_SRC" "$FZFRC"

cat > "$SHIM/ai-agent-list" <<'SH'
#!/usr/bin/env bash
if [ "${NO_AGENTS:-}" = 1 ]; then exit 0; fi
printf '%s\n' "${AGENT_ROW:-%7|running|Claude|proj|/p/proj|Fix it}"
SH

cat > "$SHIM/fzf" <<'SH'
#!/usr/bin/env bash
{
  printf 'FZF_DEFAULT_OPTS=%s\n' "${FZF_DEFAULT_OPTS-<unset>}"
  printf 'FZF_DEFAULT_OPTS_FILE=%s\n' "${FZF_DEFAULT_OPTS_FILE-<unset>}"
  printf 'ARGS=%s\n' "$*"
} >> "$FZF_LOG"
if [ "${FZF_CANCEL:-}" = 1 ]; then
  cat >/dev/null
  exit 1
fi
IFS= read -r line || exit 0
printf '%s\n' "$line"
cat >/dev/null
SH

cat > "$SHIM/uname" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_UNAME:-Linux}"
SH

cat > "$SHIM/tmux" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  list-panes) printf '%%7 session 2\n' ;;
  display-message) printf '/dev/pts/1|1234\n' ;;
  switch-client|select-window|select-pane) printf '%s\n' "$*" >> "$TMUX_LOG" ;;
esac
exit 0
SH

cat > "$SHIM/hypr-tmux-client" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HYPR_LOG"
SH

cat > "$SHIM/open" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$OPEN_LOG"
SH

chmod +x "$SHIM"/*

pass=0
fail=0
ok() { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() {
  printf 'FAIL  %s\n      %s\n' "$1" "$2"
  fail=$((fail + 1))
}
check() {
  local name=$1 expected=$2 actual=$3
  if [[ "$actual" == "$expected" ]]; then
    ok "$name"
  else
    bad "$name" "expected [$expected], got [$actual]"
  fi
}
contains() {
  local name=$1 pattern=$2 file=$3
  if grep -qF -- "$pattern" "$file" 2>/dev/null; then
    ok "$name"
  else
    bad "$name" "missing [$pattern] in $file"
  fi
}

reset_case() {
  FAKE_UNAME=Linux
  FZF_CANCEL=""
  NO_AGENTS=""
  FZF_DEFAULT_OPTS_TEST=""
  FZF_DEFAULT_OPTS_FILE_TEST=""
}

run_switcher() {
  : > "$FZF_LOG"
  : > "$TMUX_LOG"
  : > "$HYPR_LOG"
  : > "$OPEN_LOG"
  OUT=$(
    PATH="$SHIM:$PATH" \
    HOME="$HOME_DIR" \
    XDG_CONFIG_HOME="$WORK/xdg" \
    FAKE_UNAME="$FAKE_UNAME" \
    FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS_TEST" \
    FZF_DEFAULT_OPTS_FILE="$FZF_DEFAULT_OPTS_FILE_TEST" \
    FZF_CANCEL="$FZF_CANCEL" \
    NO_AGENTS="$NO_AGENTS" \
    TMUX_AGENT_OPEN_CMD="$SHIM/open" \
    FZF_LOG="$FZF_LOG" \
    TMUX_LOG="$TMUX_LOG" \
    HYPR_LOG="$HYPR_LOG" \
    OPEN_LOG="$OPEN_LOG" \
    bash "$SCRIPT"
  )
  RUN_EXIT=$?
}

case_fzfrc_contents() {
  echo "== shared fzfrc has the Nightfox settings =="
  contains "reverse layout" "--layout=reverse" "$FZFRC_SRC"
  contains "nightfox background" "--color=bg:#1a1b26" "$FZFRC_SRC"
  contains "current-line highlight" "--highlight-line" "$FZFRC_SRC"
}

case_linux_shared_theme() {
  echo "== Linux: shared fzfrc replaces inherited options =="
  reset_case
  FZF_DEFAULT_OPTS_TEST="--layout=default"
  FZF_DEFAULT_OPTS_FILE_TEST="/nonexistent/fzfrc"
  run_switcher
  check "exits 0" 0 "$RUN_EXIT"
  check "inherited FZF_DEFAULT_OPTS is cleared" \
    "FZF_DEFAULT_OPTS=<unset>" "$(grep '^FZF_DEFAULT_OPTS=' "$FZF_LOG")"
  check "FZF_DEFAULT_OPTS_FILE points at the shared rc" \
    "FZF_DEFAULT_OPTS_FILE=$FZFRC" "$(grep '^FZF_DEFAULT_OPTS_FILE=' "$FZF_LOG")"
  contains "fzf gets ansi support" "--ansi" "$FZF_LOG"
  contains "fzf opens a tmux popup" "--tmux 70%,50%" "$FZF_LOG"
  contains "fzf gets the border" "--border" "$FZF_LOG"
  contains "fzf gets the header" "--header=go to agent" "$FZF_LOG"
  contains "switch-client targets the client tty" "switch-client -c /dev/pts/1 -t session" "$TMUX_LOG"
  contains "select-window targets the window" "select-window -t session:2" "$TMUX_LOG"
  contains "select-pane targets the pane" "select-pane -t %7" "$TMUX_LOG"
  contains "the client window is focused via hypr-tmux-client" "focus /dev/pts/1 1234" "$HYPR_LOG"
}

case_darwin_focus() {
  echo "== Darwin: selection is handed to Hammerspoon =="
  reset_case
  FAKE_UNAME=Darwin
  run_switcher
  check "exits 0" 0 "$RUN_EXIT"
  contains "escaped pane URL" \
    "hammerspoon://nanowm?cmd=focusAgent&pane=%257" "$OPEN_LOG"
}

case_no_agents() {
  echo "== no agents: exits before fzf =="
  reset_case
  NO_AGENTS=1
  run_switcher
  check "exits 0" 0 "$RUN_EXIT"
  check "fzf is not invoked" "" "$(cat "$FZF_LOG")"
}

case_cancel() {
  echo "== cancel: no focus action =="
  reset_case
  FZF_CANCEL=1
  run_switcher
  check "exits 0" 0 "$RUN_EXIT"
  check "no tmux focus" "" "$(cat "$TMUX_LOG")"
  check "no hypr-tmux-client focus" "" "$(cat "$HYPR_LOG")"
}

case_missing_fzfrc() {
  echo "== missing fzfrc: inherited options are left alone =="
  reset_case
  rm -f "$FZFRC"
  FZF_DEFAULT_OPTS_TEST="--layout=default"
  FZF_DEFAULT_OPTS_FILE_TEST="/nonexistent/fzfrc"
  run_switcher
  check "exits 0" 0 "$RUN_EXIT"
  check "inherited FZF_DEFAULT_OPTS is kept" \
    "FZF_DEFAULT_OPTS=--layout=default" "$(grep '^FZF_DEFAULT_OPTS=' "$FZF_LOG")"
  check "stale FZF_DEFAULT_OPTS_FILE is cleared" \
    "FZF_DEFAULT_OPTS_FILE=<unset>" "$(grep '^FZF_DEFAULT_OPTS_FILE=' "$FZF_LOG")"
}

case_fzfrc_contents
case_linux_shared_theme
case_darwin_focus
case_no_agents
case_cancel
case_missing_fzfrc

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then
  printf 'scratch kept for inspection: %s\n' "$WORK"
  exit 1
fi
rm -rf "$WORK"
