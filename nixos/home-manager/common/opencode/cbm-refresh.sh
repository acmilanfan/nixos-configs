#!/usr/bin/env bash
# cbm-refresh — refresh a codebase-memory-mcp project only when its checkout
# changed since the last successful refresh.
#
# The read-only scout MCP profile never registers CBM's background watcher, and
# an index silently goes stale on any commit or uncommitted edit. Run this before
# trusting structural graph results, or use --check to detect staleness first.
set -euo pipefail

prog=${0##*/}

usage() {
  cat <<EOF
Usage: $prog [PATH] [--check] [--force] [--mode MODE]

Reindex a codebase-memory-mcp project when its git checkout changed since the
last refresh. A git repository is required.

  PATH        project directory (default: current directory)
  --check     report freshness only; exit 1 when a refresh is needed
  --force     reindex even when the recorded signature matches
  --mode M    index mode: moderate (default), full, or fast
  --name N    project name (default: the registered name, else the dir name)

Exit: 0 up to date or refreshed, 1 stale (--check), 2 error.
EOF
}

mode=moderate name='' path='' check=0 force=0
while (($#)); do
  case $1 in
    --check) check=1 ;;
    --force) force=1 ;;
    --mode) mode=${2:?$prog: --mode needs a value}; shift ;;
    --mode=*) mode=${1#--mode=} ;;
    --name) name=${2:?$prog: --name needs a value}; shift ;;
    --name=*) name=${1#--name=} ;;
    -h | --help) usage; exit 0 ;;
    --)
      shift
      path=${1:-.}
      break
      ;;
    -*) echo "$prog: unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) path=$1 ;;
  esac
  shift
done
path=${path:-.}

case $mode in
  moderate | full | fast) ;;
  *) echo "$prog: invalid --mode '$mode' (moderate|full|fast)" >&2; exit 2 ;;
esac

bin=${CBM_BIN:-codebase-memory-mcp}

if ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
  echo "$prog: not a git repository: $path" >&2
  exit 2
fi
root=$(cd "$path" && pwd -P)
head=$(git -C "$root" rev-parse --verify HEAD 2>/dev/null || echo '(no-commits)')
# Fold HEAD and the scoped dirty state (matching CBM's own git watcher) into one
# signature, so a commit, a branch switch, or an uncommitted edit all count.
# Hash content, not just porcelain paths: a second edit to a file that is
# already modified (or untracked) must change the signature too.
scope=(-- . ':(exclude).codebase-memory')
dirty=$(
  git -C "$root" status --porcelain -uall "${scope[@]}"
  git -C "$root" diff --binary "${scope[@]}"
  git -C "$root" diff --cached --binary "${scope[@]}"
  while IFS= read -r -d '' file; do
    printf '%s ' "$file"
    git -C "$root" hash-object -- "$file"
  done < <(git -C "$root" ls-files -z -o --exclude-standard "${scope[@]}")
)
signature=$(printf '%s\n%s' "$head" "$dirty" | git -C "$root" hash-object --stdin)

state_dir=${CBM_REFRESH_STATE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/codebase-memory-mcp/cbm-refresh}
state_file="$state_dir/$(printf '%s' "$root" | git hash-object --stdin)"

if [[ -z $name ]]; then
  name=$(
    "$bin" cli --quiet list_projects --format json 2>/dev/null |
      jq -r --arg root "$root" '.projects[]? | select(.root_path == $root) | .name' 2>/dev/null |
      head -n1
  ) || true
  [[ -n $name ]] || name=${root##*/}
fi

fresh=0
if [[ -f $state_file && $(cat "$state_file") == "$signature" ]]; then
  fresh=1
fi

if ((fresh)) && ((!force)); then
  if ((check)); then echo "fresh: $root"; else echo "up to date: $root"; fi
  exit 0
fi

if ((check)); then
  echo "stale: $root"
  exit 1
fi

if ((force)) && ((fresh)); then
  echo "$prog: forcing refresh of unchanged checkout: $root" >&2
fi
"$bin" cli --quiet index_repository --repo-path "$root" --name "$name" --mode "$mode" >/dev/null
mkdir -p "$state_dir"
printf '%s' "$signature" >"$state_file"
echo "refreshed: $root"
