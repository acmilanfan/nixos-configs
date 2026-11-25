#!/usr/bin/env bash
# Tests for ../wt-setup: the local files it links or writes into a worktree
# are added to info/exclude, so the worktree stays clean for wt-prune, while
# files a user writes in the worktree itself still show up as changes.
#
# direnv is a stub (nothing is trusted), and the fixture lives outside the
# project roots, so tech-envrc never runs; the `use_tech` .envrc it would
# write is created by hand.
#
# Usage: bash nixos/home-manager/common/scripts/tests/wt-setup.test.sh
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wt-setup-test.XXXXXX")" && pwd -P)
SHIM="$WORK/shim"
mkdir -p "$SHIM"
printf '#!/usr/bin/env bash\nexit 1\n' > "$SHIM/direnv"
chmod +x "$SHIM/direnv"

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

pass=0
fail=0
check() { # check <name> <condition...>
  local name=$1
  shift
  if "$@"; then
    printf 'PASS  %s\n' "$name"
    pass=$((pass + 1))
  else
    printf 'FAIL  %s\n      status: %s\n      exclude: %s\n' "$name" \
      "$(git -C "$WT" status --porcelain | tr '\n' ';')" \
      "$(tr '\n' ';' < "$REPO/.git/info/exclude" 2>/dev/null)"
    fail=$((fail + 1))
  fi
}

run_setup() { PATH="$SHIM:$PATH" bash "$SCRIPT_DIR/wt-setup" "$WT" > /dev/null 2>&1; }
status_is() { [ "$(git -C "$WT" status --porcelain)" = "$1" ]; }

# main checkout with untracked local files, one tracked .env.example
REPO="$WORK/repo"
WT="$WORK/repo-feat"
mkdir -p "$REPO/.claude"
git -C "$REPO" init -q -b main
echo base > "$REPO/file.txt"
echo EXAMPLE=1 > "$REPO/.env.example"
git -C "$REPO" add file.txt .env.example
git -C "$REPO" commit -qm base
echo SECRET=1 > "$REPO/.env"
echo LOCAL=1 > "$REPO/.env.local"
echo '{}' > "$REPO/.claude/settings.local.json"
git -C "$REPO" worktree add -q -b feat "$WT"
printf 'use_tech\n' > "$WT/.envrc"

run_setup
check "setup succeeds" test $? -eq 0
check ".env is linked" test -L "$WT/.env"
check "worktree is clean after setup" status_is ""
check "tracked .env.example is not excluded" bash -c '! grep -qx "/.env.example" "$1"' _ "$REPO/.git/info/exclude"

lines=$(wc -l < "$REPO/.git/info/exclude")
run_setup
check "re-run adds no duplicate lines" test "$(wc -l < "$REPO/.git/info/exclude")" -eq "$lines"

echo X=1 > "$WT/.env.test"
check "a real .env file in the worktree still shows" status_is "?? .env.test"
rm "$WT/.env.test"

printf 'use flake\n' > "$WT/.envrc"
check "an edited .envrc stays excluded once added" status_is ""

check "worktree remove succeeds without --force" \
  git -C "$REPO" worktree remove "$WORK/repo-feat"
check "the main checkout's .env survives the removal" test -s "$REPO/.env"

# a .envrc that was not ours from the start is never excluded
WT2="$WORK/repo-other"
git -C "$REPO" worktree add -q -b other "$WT2"
WT=$WT2
sed -i.bak '/^\/\.envrc$/d' "$REPO/.git/info/exclude" && rm -f "$REPO/.git/info/exclude.bak"
printf 'use flake\n' > "$WT/.envrc"
run_setup
check "a user-written .envrc is not excluded" status_is "?? .envrc"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then
  printf 'scratch kept for inspection: %s\n' "$WORK"
  exit 1
fi
rm -rf "$WORK"
