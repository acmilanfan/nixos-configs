#!/usr/bin/env bash
# Tests for ../ai-agent-list ordering.
#
# Contract under test:
#   - needs-input rows come first, regardless of age
#   - everything else is most-recent state-hook event first
#   - panes with no recorded event (no hook state) keep their existing
#     tmux list-panes order and sort after every timestamped pane
#   - the six-field output format is unchanged (pane|state|type|project|cwd|title)
#
# The recency timestamp is the pane option @agent_state_updated, set by the
# agent-state wrapper in tmux.nix. Panes are stubbed through a fake `tmux`
# and a fake `ps`, so no live tmux server or real agents are involved.
#
# Usage: bash nixos/home-manager/common/scripts/tests/ai-agent-list.test.sh
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$SCRIPT_DIR/ai-agent-list"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/ai-agent-list-test.XXXXXX")
SHIM="$WORK/shim"
mkdir -p "$SHIM"

# tmux stand-in. The script only uses these four invocations.
cat > "$SHIM/tmux" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  show-environment)
    cat "${FIXTURE_DIR}/env" 2>/dev/null
    ;;
  list-panes)
    cat "${FIXTURE_DIR}/panes"
    ;;
  capture-pane)
    [ -n "${CONFIRM:-}" ] && printf '%s\n' "${CONFIRM}"
    ;;
  set-environment)
    printf '%s\n' "$*" >> "${FIXTURE_DIR}/envlog"
    ;;
esac
exit 0
SH

# ps stand-in: tty, cpu%, command line (the script asks for this exact format).
cat > "$SHIM/ps" <<'SH'
#!/usr/bin/env bash
cat "${FIXTURE_DIR}/ps" 2>/dev/null
SH

cat > "$SHIM/hostname" <<'SH'
#!/usr/bin/env bash
printf '%s\n' testhost
SH

chmod +x "$SHIM/tmux" "$SHIM/ps" "$SHIM/hostname"

pass=0
fail=0
ok() { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() {
  printf 'FAIL  %s\n      %s\n' "$1" "$2"
  fail=$((fail + 1))
}

# fixture <name> — resets the per-case input files.
fixture() {
  FIXTURE_DIR="$WORK/$1"
  mkdir -p "$FIXTURE_DIR"
  : > "$FIXTURE_DIR/env"
  : > "$FIXTURE_DIR/panes"
  : > "$FIXTURE_DIR/ps"
  : > "$FIXTURE_DIR/envlog"
  CONFIRM=""
}

# Agenty command line on a tty, so phase 1 verification finds a live process.
agent_ps() { printf '%s 0.0 opencode\n' "$1" >> "$FIXTURE_DIR/ps"; }

# hook_pane <pane> <agent> <state> — one env-tracked pane.
hook_pane() {
  printf 'TMUX_AGENT_PANE_%s_STATE=%s\nTMUX_AGENT_PANE_%s_AGENT=%s\n' \
    "$1" "$3" "$1" "$2" >> "$FIXTURE_DIR/env"
}

# pane_row <pane> <tty> <cwd> <updated> <title> — one list-panes row.
pane_row() {
  printf '%s|12345|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "$5" >> "$FIXTURE_DIR/panes"
}

# run_list — sets OUT to the script's stdout.
run_list() {
  OUT=$(PATH="$SHIM:$PATH" FIXTURE_DIR="$FIXTURE_DIR" CONFIRM="$CONFIRM" bash "$SCRIPT")
  RUN_EXIT=$?
}

ids() { printf '%s\n' "$OUT" | cut -d'|' -f1 | paste -sd' ' -; }

case_recent_first() {
  echo "== most recent event first, not pane-id order =="
  fixture recent
  hook_pane %11 opencode idle
  hook_pane %2 claude running
  hook_pane %3 gemini done
  agent_ps ttys011
  agent_ps ttys002
  agent_ps ttys003
  pane_row %11 /dev/ttys011 /p/one 100 "old"
  pane_row %2 /dev/ttys002 /p/two 300 "newest"
  pane_row %3 /dev/ttys003 /p/three 200 "middle"
  run_list
  [[ "$RUN_EXIT" -eq 0 ]] &&
    ok "exits 0" ||
    bad "exits 0" "exit $RUN_EXIT"
  [[ "$(ids)" == "%2 %3 %11" ]] &&
    ok "newest event first (%2 300, %3 200, %11 100)" ||
    bad "newest event first (%2 300, %3 200, %11 100)" "order: $(ids)"
  [[ "$(printf '%s\n' "$OUT" | head -1)" == "%2|running|Claude|two|/p/two|newest" ]] &&
    ok "row format is unchanged (pane|state|type|project|cwd|title)" ||
    bad "row format is unchanged" "first row: $(printf '%s\n' "$OUT" | head -1)"
}

case_needs_input_first() {
  echo "== needs-input is pinned above newer rows =="
  fixture confirm
  hook_pane %2 claude running
  hook_pane %3 gemini needs-input
  hook_pane %4 opencode needs-input
  agent_ps ttys002
  agent_ps ttys003
  agent_ps ttys004
  pane_row %2 /dev/ttys002 /p/two 900 "busy"
  pane_row %3 /dev/ttys003 /p/three 100 "waiting on you"
  pane_row %4 /dev/ttys004 /p/four 500 "also waiting"
  run_list
  [[ "$(ids)" == "%4 %3 %2" ]] &&
    ok "needs-input rows come first, newest of them first" ||
    bad "needs-input rows come first, newest of them first" "order: $(ids)"
  [[ "$(printf '%s\n' "$OUT" | head -1 | cut -d'|' -f2)" == "needs-input" ]] &&
    ok "the first row is the needs-input one" ||
    bad "the first row is the needs-input one" "first row: $(printf '%s\n' "$OUT" | head -1)"
}

case_untimestamped_last() {
  echo "== pane with no recorded event sorts last =="
  fixture no-event
  hook_pane %2 claude running
  hook_pane %10 gemini idle
  agent_ps ttys002
  agent_ps ttys010
  pane_row %2 /dev/ttys002 /p/two 100 "seen"
  pane_row %10 /dev/ttys010 /p/ten "" "never fired"
  run_list
  [[ "$(ids)" == "%2 %10" ]] &&
    ok "timestamped row sorts before the untimestamped one" ||
    bad "timestamped row sorts before the untimestamped one" "order: $(ids)"
}

case_fallback_block() {
  echo "== fallback (unhooked) panes keep tmux order, after hooked ones =="
  fixture fallback
  hook_pane %5 opencode running
  agent_ps ttys005
  agent_ps ttys009
  agent_ps ttys010
  pane_row %9 /dev/ttys009 /p/nine "" "fallback one"
  pane_row %5 /dev/ttys005 /p/five 50 "hooked"
  pane_row %10 /dev/ttys010 /p/ten "" "fallback two"
  run_list
  [[ "$(ids)" == "%5 %9 %10" ]] &&
    ok "hooked row first, then fallback rows in list-panes order" ||
    bad "hooked row first, then fallback rows in list-panes order" "order: $(ids)"
}

case_stale_env_cleanup() {
  echo "== stale hook state for a dead pane is still cleaned up =="
  fixture stale
  hook_pane %99 claude running
  agent_ps ttys001
  pane_row %1 /dev/ttys001 /p/one 10 "alive"
  run_list
  [[ "$(ids)" == "%1" ]] &&
    ok "dead pane is not listed" ||
    bad "dead pane is not listed" "order: $(ids)"
  [[ "$(grep -c 'TMUX_AGENT_PANE_%99_STATE' "$FIXTURE_DIR/envlog")" == 1 ]] &&
    ok "dead pane's STATE is unset" ||
    bad "dead pane's STATE is unset" "log: $(cat "$FIXTURE_DIR/envlog")"
  [[ "$(grep -c 'TMUX_AGENT_PANE_%99_AGENT' "$FIXTURE_DIR/envlog")" == 1 ]] &&
    ok "dead pane's AGENT is unset" ||
    bad "dead pane's AGENT is unset" "log: $(cat "$FIXTURE_DIR/envlog")"
}

case_title_and_cleanup() {
  echo "== title parsing survives the extra format field =="
  fixture title
  hook_pane %2 opencode done
  agent_ps ttys002
  pane_row %2 /dev/ttys002 /p/two 42 "OC | fix the thing"
  run_list
  [[ "$(printf '%s\n' "$OUT" | cut -d'|' -f6)" == "fix the thing" ]] &&
    ok "OpenCode's 'OC | <title>' prefix is stripped" ||
    bad "OpenCode's 'OC | <title>' prefix is stripped" "row: $OUT"
}

case_confirm_detection() {
  echo "== confirmation prompt still forces needs-input and pins the row =="
  fixture confirm-prompt
  hook_pane %2 claude idle
  hook_pane %3 gemini idle
  agent_ps ttys002
  agent_ps ttys003
  pane_row %2 /dev/ttys002 /p/two 10 "older"
  pane_row %3 /dev/ttys003 /p/three 99 "newer"
  CONFIRM="Do you want to proceed?"
  run_list
  [[ "$(printf '%s\n' "$OUT" | head -1 | cut -d'|' -f1)" == "%3" ]] &&
    ok "the pane asking for confirmation moves to the top" ||
    bad "the pane asking for confirmation moves to the top" "order: $(ids)"
}

case_recent_first
case_needs_input_first
case_untimestamped_last
case_fallback_block
case_stale_env_cleanup
case_title_and_cleanup
case_confirm_detection

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then
  printf 'scratch kept for inspection: %s\n' "$WORK"
  exit 1
fi
rm -rf "$WORK"
