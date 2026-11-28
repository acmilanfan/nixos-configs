#!/usr/bin/env bash
# Tests for ../hypr-ai-agents tmux server selection.
#
# Contract under test:
#   - outside tmux, with no TMUX_TMPDIR, use the same secure socket Home
#     Manager's programs.tmux.secureSocket gives login shells
#   - an explicit TMUX_TMPDIR is left alone
#   - inside tmux, TMUX decides the socket; do not override TMUX_TMPDIR
#
# The menu is launched from Hyprland/Quickshell/Waybar, which do not source a
# login shell, so they had no TMUX_TMPDIR and talked to the default /tmp
# server instead of the user's attached /run one.
#
# Usage: bash nixos/home-manager/common/scripts/tests/hypr-ai-agents.test.sh
set -uo pipefail

if [[ ${OSTYPE:-} != linux* ]]; then
  echo "SKIP  hypr-ai-agents is Linux-only (OSTYPE=${OSTYPE:-unset})"
  exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$SCRIPT_DIR/hypr-ai-agents"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/hypr-ai-agents-test.XXXXXX")
SHIM="$WORK/shim"
LOG="$WORK/calls"
mkdir -p "$SHIM"

cat > "$SHIM/tmux" <<'SH'
#!/usr/bin/env bash
printf 'tmux %s [TMUX_TMPDIR=%s]\n' "$*" "${TMUX_TMPDIR-<unset>}" >> "$LOG"
case "${1:-}" in
  list-panes)  printf '%%1 nixos-configs 1\n' ;;
  list-clients) printf '/dev/pts/9|1234|100\n' ;;
esac
exit 0
SH

cat > "$SHIM/hypr-tmux-client" <<'SH'
#!/usr/bin/env bash
printf 'hypr-tmux-client %s\n' "$*" >> "$LOG"
SH

cat > "$SHIM/ai-agent-list" <<'SH'
#!/usr/bin/env bash
printf '%%1|running|OpenCode|proj|/p|agent title\n'
printf '%%2|idle|Claude|proj|/p|other title\n'
SH

chmod +x "$SHIM/tmux" "$SHIM/hypr-tmux-client" "$SHIM/ai-agent-list"

export LOG

pass=0
fail=0
ok() { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() {
  printf 'FAIL  %s\n      %s\n' "$1" "$2"
  fail=$((fail + 1))
}

# run_focus [env assignments...] — runs --focus with a clean tmux environment.
run_focus() {
  : > "$LOG"
  env -u TMUX -u TMUX_TMPDIR "$@" \
    PATH="$SHIM:$PATH" XDG_RUNTIME_DIR=/run/user/1234 \
    bash "$SCRIPT" --focus %1 >/dev/null 2>&1
  RUN_EXIT=$?
}

case_secure_socket() {
  echo "== outside tmux uses the login-shell secure socket =="
  run_focus
  [[ "$RUN_EXIT" -eq 0 ]] &&
    ok "exits 0" ||
    bad "exits 0" "exit $RUN_EXIT"
  tmux_calls=$(grep -c '^tmux ' "$LOG")
  secure_calls=$(grep -c 'TMUX_TMPDIR=/run/user/1234' "$LOG")
  [[ "$tmux_calls" -gt 0 && "$tmux_calls" -eq "$secure_calls" ]] &&
    ok "every tmux call uses TMUX_TMPDIR=/run/user/1234" ||
    bad "every tmux call uses TMUX_TMPDIR=/run/user/1234" "calls: $(tr '\n' ';' < "$LOG")"
  grep -q "hypr-tmux-client focus /dev/pts/9 1234" "$LOG" &&
    ok "focuses the client's terminal window after switching" ||
    bad "focuses the client's terminal window after switching" "calls: $(tr '\n' ';' < "$LOG")"
}

case_explicit_tmpdir() {
  echo "== explicit TMUX_TMPDIR wins =="
  run_focus TMUX_TMPDIR=/custom/tmux
  grep -q 'TMUX_TMPDIR=/custom/tmux' "$LOG" &&
    ok "keeps TMUX_TMPDIR=/custom/tmux" ||
    bad "keeps TMUX_TMPDIR=/custom/tmux" "calls: $(tr '\n' ';' < "$LOG")"
}

case_inside_tmux() {
  echo "== inside tmux, TMUX decides and TMUX_TMPDIR is untouched =="
  : > "$LOG"
  env -u TMUX_TMPDIR TMUX=/tmp/tmux-1000/default,1,0 \
    PATH="$SHIM:$PATH" XDG_RUNTIME_DIR=/run/user/1234 \
    bash "$SCRIPT" --focus %1 >/dev/null 2>&1
  grep -q 'TMUX_TMPDIR=<unset>' "$LOG" &&
    ok "does not invent a conflicting TMUX_TMPDIR" ||
    bad "does not invent a conflicting TMUX_TMPDIR" "calls: $(tr '\n' ';' < "$LOG")"
}

case_opencode_label() {
  echo "== OpenCode agents appear in the bar label =="
  out=$(env -u TMUX -u TMUX_TMPDIR \
    PATH="$SHIM:$PATH" XDG_RUNTIME_DIR=/run/user/1234 \
    bash "$SCRIPT")
  text=$(printf '%s' "$out" | jq -r '.text // ""')
  [[ "$text" == *"O:1"* ]] &&
    ok "OpenCode-only agents are counted (got '$text')" ||
    bad "OpenCode-only agents are counted" "output: $out"
  [[ "$text" == *"C:1"* ]] &&
    ok "existing Claude count still appears (got '$text')" ||
    bad "existing Claude count still appears" "output: $out"
}

case_secure_socket
case_explicit_tmpdir
case_inside_tmux
case_opencode_label

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then
  printf 'scratch kept for inspection: %s\n' "$WORK"
  exit 1
fi
rm -rf "$WORK"
