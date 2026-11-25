#!/usr/bin/env bash
# Regression test for ../pr-watch's comment wakes.
#
# A failed read of the inline review comments (REST) on the first cycle used
# to leave them out of the "already seen" set, so a comment from before the
# watch started was announced as new once the read worked again.
#
# gh and tmux are stubs; a counter file drives the cycles:
#   1: inline comments fail, rc1 (from before the watch) exists
#   2: inline comments work: rc1 must stay quiet
#   3: rc2 arrives: it must be announced
#   4: the PR is closed, which ends the watch
#
# Usage: bash nixos/home-manager/common/scripts/tests/pr-watch.test.sh
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/pr-watch-test.XXXXXX")" && pwd -P)
SHIM="$WORK/shim"
mkdir -p "$SHIM"
export WORK

cat > "$SHIM/gh" <<'SH'
#!/usr/bin/env bash
cycle=$(cat "$WORK/cycle" 2>/dev/null || echo 0)
case "$*" in
  "pr view --json number,url,headRepositoryOwner,headRepository")
    echo '{"number":7,"url":"https://github.com/o/r/pull/7"}' ;;
  "pr view https://github.com/o/r/pull/7 --json"*)
    cycle=$((cycle + 1)); echo "$cycle" > "$WORK/cycle"
    state=OPEN; [ "$cycle" -ge 4 ] && state=CLOSED
    printf '{"state":"%s","mergeable":"MERGEABLE","headRefOid":"abc1234","statusCheckRollup":[],"comments":[],"reviews":[]}\n' "$state" ;;
  "api user --jq .login") echo me ;;
  "api repos/o/r/pulls/7/comments --paginate")
    case "$cycle" in
      1) exit 1 ;;
      2) echo '[{"id":1,"user":{"login":"bob"}}]' ;;
      *) echo '[{"id":1,"user":{"login":"bob"}},{"id":2,"user":{"login":"bob"}}]' ;;
    esac ;;
  "api repos/o/r/pulls/7/comments/"*)
    echo '{"id":2,"user":{"login":"bob"},"author_association":"MEMBER","body":"please fix"}' ;;
  *) echo "unexpected gh $*" >&2; exit 1 ;;
esac
SH
cat > "$SHIM/tmux" <<'SH'
#!/usr/bin/env bash
case "$1" in
  display) case "$*" in *pane_current_command*) echo claude ;; *pane_in_mode*) echo 0 ;; *) echo ;; esac ;;
  show) echo done ;;
  send-keys) shift; printf '%s\n' "$*" >> "$WORK/typed" ;;
esac
SH
chmod +x "$SHIM"/*

XDG_STATE_HOME="$WORK/state" PATH="$SHIM:$PATH" \
  bash "$SCRIPT_DIR/pr-watch" --pane %1 --interval 0 --foreground > "$WORK/log" 2>&1
code=$?

pass=0 fail=0
check() { # check <name> <condition...>
  local name=$1
  shift
  if "$@"; then
    printf 'PASS  %s\n' "$name"; pass=$((pass + 1))
  else
    printf 'FAIL  %s\n' "$name"; fail=$((fail + 1))
  fi
}
typed() { grep -c -- "$1" "$WORK/typed" 2>/dev/null || true; }

check "watch ends when the PR closes" test "$code" -eq 0
check "failed inline read is logged" grep -q 'comments skipped this cycle' "$WORK/log"
check "exactly one comment wake" test "$(typed 'new comment from')" -eq 1
check "the new comment is the one announced" grep -q 'new comment from bob: please fix' "$WORK/typed"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then
  printf 'log:\n'; cat "$WORK/log"; printf 'typed:\n'; cat "$WORK/typed" 2>/dev/null
  printf 'scratch kept for inspection: %s\n' "$WORK"
  exit 1
fi
rm -rf "$WORK"
