#!/usr/bin/env bash
# Tests for ../wt-new without a terminal (the way agents call it) and for the
# argument forms of ../worktree-switch and ../worktree-remove.
#
# tmux, wt-setup, ai-branch-name, ai-models and fzf are stubs that record
# their arguments; fzf fails the run, since nothing may be asked without a
# terminal. stdin is never a terminal here, so the interactive prompts
# themselves are not covered.
#
# Usage: bash nixos/home-manager/common/scripts/tests/wt-new.test.sh
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wt-new-test.XXXXXX")" && pwd -P)
SHIM="$WORK/shim"
LOG="$WORK/calls"
mkdir -p "$SHIM"

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

for tool in tmux wt-setup ai-models; do
  cat > "$SHIM/$tool" <<SH
#!/usr/bin/env bash
printf '%s %s\n' "$tool" "\$*" >> "$LOG"
# no session exists yet
[ "$tool \${1:-}" != "tmux has-session" ] || exit 1
SH
done
cat > "$SHIM/ai-branch-name" <<SH
#!/usr/bin/env bash
printf 'ai-branch-name %s\n' "\$*" >> "$LOG"
echo CFE-1-named-branch
SH
cat > "$SHIM/fzf" <<SH
#!/usr/bin/env bash
echo "fzf \$*" >> "$LOG"
echo "fzf must not run without a terminal" >&2
exit 1
SH
chmod +x "$SHIM"/*

pass=0
fail=0
check() { # check <name> <condition...>
  local name=$1
  shift
  if "$@"; then
    printf 'PASS  %s\n' "$name"
    pass=$((pass + 1))
  else
    printf 'FAIL  %s\n      exit %s stdout: %s\n      stderr: %s\n      calls: %s\n' \
      "$name" "$RUN_EXIT" "$RUN_OUT" "$RUN_ERR" "$(tr '\n' ';' < "$LOG" 2>/dev/null)"
    fail=$((fail + 1))
  fi
}

# fixture <name>: a repository at $WORK/<name>/repo with one commit
fixture() {
  REPO="$WORK/$1/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q -b main
  echo base > "$REPO/file.txt"
  git -C "$REPO" add file.txt
  git -C "$REPO" commit -qm base
  : > "$LOG"
}

# run <dir> <script> [args...]: stdin from /dev/null, TMUX unset. Sets
# RUN_EXIT, RUN_OUT (stdout) and RUN_ERR (stderr).
run() {
  local dir=$1 script=$2
  shift 2
  ( cd "$dir" && env -u TMUX PATH="$SHIM:$PATH" bash "$SCRIPT_DIR/$script" "$@" ) \
    < /dev/null > "$WORK/out" 2> "$WORK/err"
  RUN_EXIT=$?
  RUN_OUT=$(cat "$WORK/out")
  RUN_ERR=$(cat "$WORK/err")
}

called() { grep -qF -- "$1" "$LOG"; }
branch_of() { git -C "$1" branch --show-current; }

echo "== branch, no agent =="
fixture plain
run "$REPO" wt-new feat-x
check "exits 0" test "$RUN_EXIT" -eq 0
check "stdout is only the worktree path" test "$RUN_OUT" = "$WORK/plain/repo-feat-x"
check "worktree is on the new branch" test "$(branch_of "$WORK/plain/repo-feat-x")" = feat-x
check "wt-setup runs without tmux" called "wt-setup $WORK/plain/repo-feat-x"
check "no tmux session without an agent" bash -c "! grep -q '^tmux new-session' '$LOG'"
check "nothing is asked" bash -c "! grep -q '^fzf' '$LOG'"

echo "== same branch again reuses the worktree =="
run "$REPO" wt-new feat-x
check "exits 0" test "$RUN_EXIT" -eq 0
check "reports the existing worktree" test "$RUN_OUT" = "$WORK/plain/repo-feat-x"
check "says it exists" bash -c '[[ "$1" == *"Exists:"* ]]' _ "$RUN_ERR"

echo "== a different branch's path is refused =="
mkdir -p "$WORK/plain/repo-taken"
run "$REPO" wt-new taken
check "exits non-zero" test "$RUN_EXIT" -ne 0
check "explains the clash" bash -c '[[ "$1" == *"is not a worktree of taken"* ]]' _ "$RUN_ERR"

echo "== --base, slash in the branch, -C from elsewhere =="
fixture base
git -C "$REPO" checkout -qb other
echo other >> "$REPO/file.txt"
git -C "$REPO" commit -qam other
run "$WORK" wt-new -C "$REPO" --base main -b feat/y
check "exits 0" test "$RUN_EXIT" -eq 0
check "slash becomes a dash in the directory" test "$RUN_OUT" = "$WORK/base/repo-feat-y"
check "branch keeps its slash" test "$(branch_of "$WORK/base/repo-feat-y")" = feat/y
check "branch starts at --base" test "$(git -C "$REPO" rev-parse feat/y)" = "$(git -C "$REPO" rev-parse main)"

echo "== existing branch is checked out, not recreated =="
fixture existing
git -C "$REPO" branch kept
run "$REPO" wt-new -b kept
check "exits 0" test "$RUN_EXIT" -eq 0
check "worktree is on the existing branch" test "$(branch_of "$WORK/existing/repo-kept")" = kept

echo "== task names the branch and becomes claude's prompt =="
fixture task
run "$REPO" wt-new --agent claude "CFE-1 fix the 'thing' now"
check "exits 0" test "$RUN_EXIT" -eq 0
check "branch comes from ai-branch-name" test "$RUN_OUT" = "$WORK/task/repo-CFE-1-named-branch"
check "ai-branch-name got the task" called "ai-branch-name CFE-1 fix the 'thing' now"
check "session is created detached" called "tmux new-session -ds repo-CFE-1-named-branch -c $WORK/task/repo-CFE-1-named-branch"
check "wt-setup gets the session" called "wt-setup --tmux repo-CFE-1-named-branch"
check "claude starts with the quoted task" \
  called "tmux send-keys -t repo-CFE-1-named-branch claude CFE-1\\ fix\\ the\\ \\'thing\\'\\ now Enter"
check "client is not switched" bash -c "! grep -q 'switch-client' '$LOG'"

echo "== --branch skips naming; opencode with models =="
fixture opencode
run "$REPO" wt-new -t "do a thing" -b my.branch -a opencode -m omlx --switch
check "exits 0" test "$RUN_EXIT" -eq 0
check "ai-branch-name is not called" bash -c "! grep -q '^ai-branch-name' '$LOG'"
check "dots become underscores in the session" called "tmux new-session -ds repo-my_branch"
check "models start headless" called "ai-models omlx"
check "opencode gets --prompt" called "tmux send-keys -t repo-my_branch opencode --prompt do\\ a\\ thing Enter"
check "--switch outside tmux prints how to attach" \
  bash -c '[[ "$1" == *"tmux attach -t repo-my_branch"* ]]' _ "$RUN_ERR"

echo "== usage errors =="
fixture errors
run "$REPO" wt-new
check "no task or branch fails without a terminal" test "$RUN_EXIT" -ne 0
run "$REPO" wt-new -a vim feat
check "unknown agent fails" bash -c '[[ $1 -ne 0 && "$2" == *"unknown agent"* ]]' _ "$RUN_EXIT" "$RUN_ERR"
run "$REPO" wt-new "bad..name"
check "invalid branch fails" bash -c '[[ $1 -ne 0 && "$2" == *"invalid branch"* ]]' _ "$RUN_EXIT" "$RUN_ERR"
run "$WORK" wt-new feat
check "outside a repository fails" bash -c '[[ $1 -ne 0 && "$2" == *"not in a git repository"* ]]' _ "$RUN_EXIT" "$RUN_ERR"
run "$REPO" wt-new --help
check "--help prints the usage" bash -c '[[ $1 -eq 0 && "$2" == *"--agent NAME"* ]]' _ "$RUN_EXIT" "$RUN_OUT"

echo "== worktree-switch by argument =="
fixture switch
git -C "$REPO" worktree add -q "$WORK/switch/repo-feat-s" -b feat/s
run "$REPO" worktree-switch feat/s
check "branch selects the worktree" test "$RUN_OUT" = "$WORK/switch/repo-feat-s"
run "$REPO" worktree-switch repo-feat-s
check "directory name selects the worktree" test "$RUN_OUT" = "$WORK/switch/repo-feat-s"
run "$WORK" worktree-switch switch/repo-feat-s
check "relative path works from outside the repo" test "$RUN_OUT" = "$WORK/switch/repo-feat-s"
run "$REPO" worktree-switch nope
check "no match fails" bash -c '[[ $1 -ne 0 && "$2" == *"0 worktrees match"* ]]' _ "$RUN_EXIT" "$RUN_ERR"
run "$REPO" worktree-switch --tmux feat/s
check "--tmux outside tmux creates the session" called "tmux new-session -ds repo-feat-s -c $WORK/switch/repo-feat-s"
check "--tmux outside tmux does not switch" bash -c "! grep -q 'switch-client' '$LOG'"
check "--tmux exits 0" test "$RUN_EXIT" -eq 0

echo "== worktree-remove by argument =="
fixture remove
git -C "$REPO" worktree add -q "$WORK/remove/repo-gone" -b gone
git -C "$REPO" worktree add -q "$WORK/remove/repo-dirty" -b dirty
echo scratch > "$WORK/remove/repo-dirty/scratch.txt"
run "$WORK" worktree-remove "$WORK/remove/repo-gone"
check "clean worktree is removed by path" bash -c '[[ $1 -eq 0 && ! -d $2 ]]' _ "$RUN_EXIT" "$WORK/remove/repo-gone"
run "$REPO" worktree-remove dirty
check "dirty worktree is kept without --force" test -f "$WORK/remove/repo-dirty/scratch.txt"
check "keeping it is explained" bash -c '[[ "$1" == *"--force removes it"* ]]' _ "$RUN_ERR"
run "$REPO" worktree-remove --force --kill-session dirty
check "--force removes the dirty worktree" bash -c '[[ $1 -eq 0 && ! -d $2 ]]' _ "$RUN_EXIT" "$WORK/remove/repo-dirty"
git -C "$REPO" worktree add -q "$WORK/remove/repo-extra" -b extra
run "$REPO" worktree-remove main
check "main worktree is refused" bash -c '[[ $1 -ne 0 && -d $2 ]]' _ "$RUN_EXIT" "$REPO"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then
  printf 'scratch kept for inspection: %s\n' "$WORK"
  exit 1
fi
rm -rf "$WORK"
