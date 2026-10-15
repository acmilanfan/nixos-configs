#!/usr/bin/env bash
# Regression tests for ../worktree-remove (fuzzy worktree removal).
#
# Bugs covered (found 2026-10-15):
#  1. Untracked-only worktrees were not treated as dirty: the check used
#     `git diff` / `git diff --cached`, which ignore untracked files. git then
#     refused `worktree remove` without --force, so the worktree stayed.
#  2. git's exit status was ignored, so the script printed "Removed: <path>"
#     and exited 0 even when nothing was removed.
#  3. The worktree list was parsed with awk '{print $2}', which cut paths at
#     the first space, so such a worktree was never offered.
#  4. The force retry passed one --force, but a locked worktree needs two.
#
# Notes on the harness:
#  - fzf is stubbed, since selection is interactive.
#  - `read -p` prints its prompt only when stdin is a terminal, so the harness
#    never asserts on prompt text. Dirty handling is observed instead through a
#    stubbed `git` that records every `worktree remove` invocation and fails it.
#  - The scratch root is resolved with `pwd -P`, because git canonicalizes
#    macOS /var/folders/... paths to /private/var/folders/... in its output.
#
# Usage: bash nixos/home-manager/common/scripts/tests/worktree-remove.test.sh
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$SCRIPT_DIR/worktree-remove"
REAL_GIT=$(command -v git)

WORK=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/worktree-remove-test.XXXXXX")" && pwd -P)
ARGS_LOG="$WORK/git-remove-args"
SHIM="$WORK/shim"
GIT_SHIM="$WORK/shim-git"
mkdir -p "$SHIM" "$GIT_SHIM"

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

# fzf stand-in: print the path the test selected, but only if it was among
# the candidates (as with the real fzf), so list parsing is covered too.
cat > "$SHIM/fzf" <<'SH'
#!/usr/bin/env bash
grep -qxF -- "$SELECTED" && printf '%s\n' "$SELECTED"
exit 0
SH

# git stand-in: records `worktree remove` calls and fails them, so the
# "removal failed" paths can be exercised without harming a real checkout.
# Every other call goes to the real git.
cat > "$GIT_SHIM/git" <<SH
#!/usr/bin/env bash
case " \$* " in
  *" worktree remove "*)
    printf '%s\n' "\$*" >> "$ARGS_LOG"
    echo "fatal: simulated removal failure" >&2
    exit 128
    ;;
esac
exec "$REAL_GIT" "\$@"
SH
chmod +x "$SHIM/fzf" "$GIT_SHIM/git"

KILL_LOG="$WORK/kill-log"
BASH_ENV_FILE="$WORK/bash-env"
# `kill` is a shell builtin, so a PATH stub only wins once the builtin is
# disabled in the script's own shell.
printf 'enable -n kill\n' > "$BASH_ENV_FILE"

# pgrep/lsof/kill stand-ins for the orphaned-nvim cleanup: two fake nvim PIDs
# (verified unused before the case runs), 999991 with its cwd inside $WT and
# 999992 elsewhere, and kills recorded instead of signalled. The lsof stub
# mirrors the real formats: `-a -p PID -d cwd -F n` prints only the cwd record,
# while `-p PID -F n` lists every open file.
write_proc_shims() {
  local dir=$1
  mkdir -p "$dir"
  cat > "$dir/pgrep" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 999991 999992
SH
  cat > "$dir/lsof" <<SH
#!/usr/bin/env bash
pid=""; want_cwd=0
while (( \$# )); do
  case \$1 in
    -p) pid=\$2; shift 2 ;;
    -d) [[ \${2:-} == cwd ]] && want_cwd=1; shift 2 ;;
    *) shift ;;
  esac
done
case \$pid in
  999991) cwd=$WT ;;
  999992) cwd=/somewhere/else ;;
  *) exit 1 ;;
esac
if (( want_cwd )); then
  printf 'p%s\nfcwd\nn%s\n' "\$pid" "\$cwd"
else
  printf 'p%s\nfcwd\nn%s\nftxt\nn/nix/store/example/bin/nvim\nf2\nn/dev/null\n' "\$pid" "\$cwd"
fi
SH
  cat > "$dir/kill" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$KILL_LOG"
SH
  chmod +x "$dir/pgrep" "$dir/lsof" "$dir/kill"
}

pass=0
fail=0
ok() { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() {
  printf 'FAIL  %s\n      %s\n' "$1" "$2"
  fail=$((fail + 1))
}

# fixture <name>: main worktree plus one linked worktree, both clean.
fixture() {
  MAIN="$WORK/$1/main"
  WT="$WORK/$1/wt-$1"
  mkdir -p "$MAIN"
  git -C "$MAIN" init -q
  echo base > "$MAIN/file.txt"
  git -C "$MAIN" add file.txt
  git -C "$MAIN" commit -qm base
  git -C "$MAIN" worktree add -q "$WT" -b "feat-${1// /-}"
}

# run_script <stdin> [fake-git] [extra-shim-dir] — runs the script from inside
# the selected worktree. Sets RUN_EXIT, RUN_OUT (stdout) and RUN_ERR (stderr).
run_script() {
  local input=$1 fakegit=${2:-} extra=${3:-}
  local path="$SHIM:$PATH"
  local -a envs=(SELECTED="$WT")
  [[ -n "$fakegit" ]] && path="$GIT_SHIM:$path"
  if [[ -n "$extra" ]]; then
    path="$extra:$path"
    envs+=(BASH_ENV="$BASH_ENV_FILE")
  fi
  envs+=(PATH="$path")
  ( cd "$WT" && printf '%b' "$input" | env "${envs[@]}" bash "$SCRIPT" ) \
    > "$WORK/out" 2> "$WORK/err"
  RUN_EXIT=$?
  RUN_OUT=$(cat "$WORK/out")
  RUN_ERR=$(cat "$WORK/err")
}

listed() { git -C "$MAIN" worktree list | grep -qF "$WT"; }
attempts() {
  [[ -f "$ARGS_LOG" ]] && wc -l < "$ARGS_LOG" | tr -d ' ' || echo 0
}
attempt() { sed -n "${1}p" "$ARGS_LOG" 2>/dev/null; }

case_untracked_decline() {
  echo "== untracked-only worktree, decline removal =="
  fixture untracked-decline
  echo scratch > "$WT/scratch.txt"
  rm -f "$ARGS_LOG"
  run_script 'n\n' fake-git
  [[ "$(attempts)" == 0 ]] &&
    ok "untracked-only worktree is treated as dirty (no removal attempted)" ||
    bad "untracked-only worktree is treated as dirty (no removal attempted)" \
        "git was asked to remove anyway: $(attempt 1)"
  [[ "$RUN_OUT" != *"Removed:"* ]] &&
    ok "declined removal is not reported as removed" ||
    bad "declined removal is not reported as removed" "stdout: $RUN_OUT"
  listed && [[ -f "$WT/scratch.txt" ]] &&
    ok "declined worktree and its untracked file are untouched" ||
    bad "declined worktree and its untracked file are untouched" \
        "listed=$(listed && echo yes || echo no) scratch=$([[ -f "$WT/scratch.txt" ]] && echo yes || echo no)"
  [[ $RUN_EXIT -eq 0 ]] &&
    ok "declining exits 0" ||
    bad "declining exits 0" "exit $RUN_EXIT"
}

case_untracked_accept() {
  echo "== untracked-only worktree, accept removal =="
  fixture untracked-accept
  echo scratch > "$WT/scratch.txt"
  run_script 'y\n'
  [[ "$RUN_OUT" == *"Removed:"* ]] &&
    ok "accepted removal is reported" ||
    bad "accepted removal is reported" "stdout: $RUN_OUT stderr: $RUN_ERR"
  ! listed && [[ ! -d "$WT" ]] &&
    ok "accepted worktree is actually gone" ||
    bad "accepted worktree is actually gone" \
        "listed=$(listed && echo yes || echo no) dir=$([[ -d "$WT" ]] && echo yes || echo no)"
  [[ $RUN_EXIT -eq 0 ]] &&
    ok "successful removal exits 0" ||
    bad "successful removal exits 0" "exit $RUN_EXIT stderr: $RUN_ERR"
}

case_tracked_decline() {
  echo "== tracked modification, decline removal (existing behaviour) =="
  fixture tracked-decline
  echo changed >> "$WT/file.txt"
  rm -f "$ARGS_LOG"
  run_script 'n\n' fake-git
  [[ "$(attempts)" == 0 ]] &&
    ok "tracked changes still count as dirty" ||
    bad "tracked changes still count as dirty" "git was asked to remove anyway: $(attempt 1)"
  [[ "$RUN_OUT" != *"Removed:"* ]] &&
    ok "declined tracked worktree is not reported as removed" ||
    bad "declined tracked worktree is not reported as removed" "stdout: $RUN_OUT"
  listed &&
    ok "declined tracked worktree is left in place" ||
    bad "declined tracked worktree is left in place" "worktree is gone"
}

case_remove_failure_eof() {
  echo "== removal fails, no answer given =="
  fixture remove-failure-eof
  rm -f "$ARGS_LOG"
  run_script '' fake-git
  [[ "$RUN_OUT" != *"Removed:"* ]] &&
    ok "failed removal is not reported as removed" ||
    bad "failed removal is not reported as removed" "stdout: $RUN_OUT"
  [[ $RUN_EXIT -ne 0 ]] &&
    ok "failed removal exits non-zero" ||
    bad "failed removal exits non-zero" "exit $RUN_EXIT"
  [[ "$RUN_ERR" == *"Failed to remove"* ]] &&
    ok "failed removal is reported on stderr" ||
    bad "failed removal is reported on stderr" "stderr: $RUN_ERR"
  listed &&
    ok "failed removal leaves the worktree registered" ||
    bad "failed removal leaves the worktree registered" "worktree is gone"
  [[ "$(attempts)" == 1 && "$(attempt 1)" != *--force* ]] &&
    ok "unanswered failure does not force" ||
    bad "unanswered failure does not force" "attempts: $(attempts); first: $(attempt 1)"
}

case_remove_failure_force() {
  echo "== removal fails, force retry accepted =="
  fixture remove-failure-force
  rm -f "$ARGS_LOG"
  run_script 'y\n' fake-git
  [[ "$RUN_OUT" != *"Removed:"* ]] &&
    ok "failed forced removal is not reported as removed" ||
    bad "failed forced removal is not reported as removed" "stdout: $RUN_OUT"
  [[ $RUN_EXIT -ne 0 ]] &&
    ok "failed forced removal exits non-zero" ||
    bad "failed forced removal exits non-zero" "exit $RUN_EXIT"
  [[ "$(attempts)" == 2 && "$(attempt 2)" == *--force* ]] &&
    ok "force retry passes --force" ||
    bad "force retry passes --force" "attempts: $(attempts); second: $(attempt 2)"
  listed &&
    ok "failed forced removal leaves the worktree registered" ||
    bad "failed forced removal leaves the worktree registered" "worktree is gone"
}

case_space_in_path() {
  echo "== worktree path with a space =="
  fixture "with space"
  run_script ''
  [[ "$RUN_OUT" == *"Removed: $WT"* ]] &&
    ok "a path with a space is offered and removed" ||
    bad "a path with a space is offered and removed" "stdout: $RUN_OUT stderr: $RUN_ERR"
  ! listed && [[ ! -d "$WT" ]] &&
    ok "worktree with a space is actually gone" ||
    bad "worktree with a space is actually gone" "listed=$(listed && echo yes || echo no)"
}

case_locked_force() {
  echo "== locked worktree, force retry accepted =="
  fixture locked-force
  git -C "$MAIN" worktree lock --reason "on a usb disk" "$WT"
  run_script 'y\n'
  [[ "$RUN_ERR" == *"locked: on a usb disk"* ]] &&
    ok "the lock and its reason are reported" ||
    bad "the lock and its reason are reported" "stderr: $RUN_ERR"
  [[ "$RUN_OUT" == *"Removed:"* && $RUN_EXIT -eq 0 ]] && ! listed && [[ ! -d "$WT" ]] &&
    ok "locked worktree is removed after confirming" ||
    bad "locked worktree is removed after confirming" \
        "exit $RUN_EXIT listed=$(listed && echo yes || echo no) stdout: $RUN_OUT stderr: $RUN_ERR"
}

case_locked_decline() {
  echo "== locked worktree, force retry declined =="
  fixture locked-decline
  git -C "$MAIN" worktree lock "$WT"
  run_script 'n\n'
  listed && [[ -d "$WT" && $RUN_EXIT -ne 0 && "$RUN_OUT" != *"Removed:"* ]] &&
    ok "declined locked worktree stays" ||
    bad "declined locked worktree stays" "exit $RUN_EXIT stdout: $RUN_OUT"
}

case_locked_args() {
  echo "== locked worktree, failing git records the retry =="
  fixture locked-args
  git -C "$MAIN" worktree lock "$WT"
  rm -f "$ARGS_LOG"
  run_script 'y\n' fake-git
  [[ "$(attempt 2)" == *"--force --force"* ]] &&
    ok "locked retry passes --force twice" ||
    bad "locked retry passes --force twice" "second: $(attempt 2)"
}

case_nvim_orphan() {
  echo "== orphaned nvim cleanup =="
  local pid
  for pid in 999991 999992; do
    if kill -0 "$pid" 2>/dev/null; then
      bad "fake nvim PIDs are free" "PID $pid exists; refusing to exercise the kill path"
      return
    fi
  done
  fixture nvim-orphan
  rm -f "$KILL_LOG"
  write_proc_shims "$WORK/shim-proc"
  run_script 'y\n' '' "$WORK/shim-proc"
  local kills
  kills=$(cat "$KILL_LOG" 2>/dev/null || true)
  [[ "$kills" == *999991* ]] &&
    ok "nvim whose cwd is the worktree is killed" ||
    bad "nvim whose cwd is the worktree is killed" "kills: ${kills:-none}"
  [[ "$kills" != *999992* ]] &&
    ok "nvim with an unrelated cwd is left alone" ||
    bad "nvim with an unrelated cwd is left alone" "kills: $kills"
  ! listed &&
    ok "cleanup does not interfere with the removal" ||
    bad "cleanup does not interfere with the removal" "still listed"
}

case_untracked_decline
case_untracked_accept
case_tracked_decline
case_nvim_orphan
case_remove_failure_eof
case_remove_failure_force
case_space_in_path
case_locked_force
case_locked_decline
case_locked_args

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then
  printf 'scratch kept for inspection: %s\n' "$WORK"
  exit 1
fi
rm -rf "$WORK"
