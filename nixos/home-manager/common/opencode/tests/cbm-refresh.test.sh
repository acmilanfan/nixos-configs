#!/usr/bin/env bash
# Regression tests for ../cbm-refresh.sh (signature-guarded CBM reindex).
#
# A codebase-memory index goes stale on any commit or uncommitted edit, and the
# read-only scout profile never registers the background watcher, so refreshes
# are explicit. These tests pin the guard: reindex exactly when the checkout
# changed, skip when it did not, and never reindex on --check.
#
# The CBM binary is stubbed (it logs each invocation), while real git builds the
# fixtures so HEAD/dirty signatures are genuine.
#
# Usage: bash nixos/home-manager/common/opencode/tests/cbm-refresh.test.sh
set -uo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$TEST_DIR/../cbm-refresh.sh"

WORK=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/cbm-refresh-test.XXXXXX")" && pwd -P)
SHIM="$WORK/shim"
LOG="$WORK/cbm-log"
STATE="$WORK/state"
mkdir -p "$SHIM"

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

# CBM stand-in: records every call; answers list_projects with a renamed entry
# so name reuse can be observed.
cat > "$SHIM/codebase-memory-mcp" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CBM_TEST_LOG"
case " $* " in
  *" list_projects "*)
    printf '{"projects":[{"name":"custom-proj","root_path":"%s/renamed"}],"total":1}\n' "$CBM_TEST_ROOT" ;;
  *" index_repository "*)
    printf '{"status":"ready"}\n' ;;
esac
exit 0
SH
chmod +x "$SHIM/codebase-memory-mcp"
export PATH="$SHIM:$PATH"
export CBM_TEST_LOG="$LOG" CBM_TEST_ROOT="$WORK" CBM_REFRESH_STATE_DIR="$STATE"

pass=0 fail=0
ok() { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL  %s\n      %s\n' "$1" "$2"; fail=$((fail + 1)); }

repo() { # repo <name> -> prints an initialized repo with one commit
  local dir="$WORK/$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  echo one > "$dir/a.txt"
  git -C "$dir" add a.txt
  git -C "$dir" commit -qm one
  printf '%s\n' "$dir"
}

run() { # run <path|args...>; sets OUT ERR CODE
  "$SCRIPT" "$@" > "$WORK/out" 2> "$WORK/err"
  CODE=$?
  OUT=$(cat "$WORK/out")
  ERR=$(cat "$WORK/err")
}
indexes() { if [[ -f "$LOG" ]]; then grep -c 'index_repository' "$LOG"; else echo 0; fi; }
reset_log() { : > "$LOG"; }

case_first_run() {
  echo "== first refresh indexes =="
  local dir; dir=$(repo first)
  reset_log
  run "$dir"
  [[ "$(indexes)" == 1 && $CODE -eq 0 ]] &&
    ok "first run reindexes once and exits 0" ||
    bad "first run reindexes once and exits 0" "indexes=$(indexes) exit=$CODE err=$ERR"
  [[ "$OUT" == *"refreshed"* ]] &&
    ok "first run reports a refresh" || bad "first run reports a refresh" "stdout=$OUT"
}

case_no_change_skips() {
  echo "== unchanged checkout is skipped =="
  local dir; dir=$(repo nochange)
  run "$dir" >/dev/null 2>&1
  reset_log
  run "$dir"
  [[ "$(indexes)" == 0 && $CODE -eq 0 ]] &&
    ok "second run with no changes does not reindex" ||
    bad "second run with no changes does not reindex" "indexes=$(indexes) exit=$CODE"
  [[ "$OUT" == *"up to date"* ]] &&
    ok "second run reports up to date" || bad "second run reports up to date" "stdout=$OUT"
}

case_commit_triggers() {
  echo "== a new commit triggers a refresh =="
  local dir; dir=$(repo commit)
  run "$dir" >/dev/null 2>&1
  echo two >> "$dir/a.txt"
  git -C "$dir" commit -qam two
  reset_log
  run "$dir"
  [[ "$(indexes)" == 1 ]] &&
    ok "commit since the last refresh reindexes" ||
    bad "commit since the last refresh reindexes" "indexes=$(indexes)"
}

case_dirty_triggers_then_stable() {
  echo "== an uncommitted edit refreshes once, then is stable =="
  local dir; dir=$(repo dirty)
  run "$dir" >/dev/null 2>&1
  echo scratch >> "$dir/a.txt"
  reset_log
  run "$dir"
  local first; first=$(indexes)
  reset_log
  run "$dir"
  local second; second=$(indexes)
  [[ "$first" == 1 && "$second" == 0 ]] &&
    ok "dirty edit reindexes once, a re-run with no further change skips" ||
    bad "dirty edit reindexes once, a re-run with no further change skips" "first=$first second=$second"
}

case_second_edit_stale() {
  echo "== a second edit to an already-modified or untracked file is stale =="
  local dir; dir=$(repo secondedit)
  echo one >> "$dir/a.txt"
  echo draft > "$dir/new.txt"
  run "$dir" >/dev/null 2>&1
  echo two >> "$dir/a.txt"
  reset_log
  run --check "$dir"
  local tracked=$CODE
  run "$dir" >/dev/null 2>&1
  echo more >> "$dir/new.txt"
  run --check "$dir"
  local untracked=$CODE
  [[ $tracked -eq 1 && $untracked -eq 1 ]] &&
    ok "re-edits of modified and untracked files make --check stale" ||
    bad "re-edits of modified and untracked files make --check stale" "tracked-exit=$tracked untracked-exit=$untracked"
}

case_check_stale() {
  echo "== --check reports staleness without reindexing =="
  local dir; dir=$(repo checkstale)
  run "$dir" >/dev/null 2>&1
  echo scratch >> "$dir/a.txt"
  reset_log
  run --check "$dir"
  [[ $CODE -eq 1 && "$(indexes)" == 0 && "$OUT" == *"stale"* ]] &&
    ok "--check exits 1, says stale, and does not reindex" ||
    bad "--check exits 1, says stale, and does not reindex" "exit=$CODE indexes=$(indexes) stdout=$OUT"
}

case_check_fresh() {
  echo "== --check reports freshness =="
  local dir; dir=$(repo checkfresh)
  run "$dir" >/dev/null 2>&1
  reset_log
  run --check "$dir"
  [[ $CODE -eq 0 && "$(indexes)" == 0 && "$OUT" == *"fresh"* ]] &&
    ok "--check exits 0 and says fresh" ||
    bad "--check exits 0 and says fresh" "exit=$CODE indexes=$(indexes) stdout=$OUT"
}

case_force() {
  echo "== --force reindexes an unchanged checkout =="
  local dir; dir=$(repo force)
  run "$dir" >/dev/null 2>&1
  reset_log
  run --force "$dir"
  [[ "$(indexes)" == 1 && $CODE -eq 0 ]] &&
    ok "--force overrides the signature guard" ||
    bad "--force overrides the signature guard" "indexes=$(indexes) exit=$CODE"
}

case_mode_passthrough() {
  echo "== --mode is passed to index_repository =="
  local dir; dir=$(repo mode)
  reset_log
  run --mode full "$dir"
  grep -q -- '--mode full' "$LOG" &&
    ok "--mode full reaches index_repository" ||
    bad "--mode full reaches index_repository" "log=$(cat "$LOG")"
}

case_name_reuse() {
  echo "== a registered project keeps its existing name =="
  local dir; dir=$(repo renamed)
  reset_log
  run "$dir"
  grep -q -- '--name custom-proj' "$LOG" &&
    ok "existing project name from list_projects is reused" ||
    bad "existing project name from list_projects is reused" "log=$(cat "$LOG")"
}

case_non_git() {
  echo "== a non-git path is an error, not a refresh =="
  local dir="$WORK/plain"
  mkdir -p "$dir"
  reset_log
  run "$dir"
  [[ $CODE -eq 2 && "$(indexes)" == 0 && "$ERR" == *"not a git repository"* ]] &&
    ok "non-git path exits 2 and does not reindex" ||
    bad "non-git path exits 2 and does not reindex" "exit=$CODE indexes=$(indexes) stderr=$ERR"
}

case_first_run
case_no_change_skips
case_commit_triggers
case_dirty_triggers_then_stable
case_check_stale
case_second_edit_stale
case_check_fresh
case_force
case_mode_passthrough
case_name_reuse
case_non_git

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if ((fail > 0)); then
  printf 'scratch kept for inspection: %s\n' "$WORK"
  exit 1
fi
rm -rf "$WORK"
