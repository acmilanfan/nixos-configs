#!/usr/bin/env bash
# Update the devshell flakes under shell/ and pin their nixpkgs to the exact
# revision the root flake.lock uses, so the shells share the system's store
# paths instead of pulling a second nixpkgs.
#
# Every shell flake declares `nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05"`,
# the same reference as the root flake, so the root's locked node can be copied
# verbatim. Run after `up` (or any root nixpkgs bump) and commit the locks.
#
# Usage: shell/update-flakes.sh [--populate]
#   --populate  also realise each devShell for the current system afterwards.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_LOCK="$SCRIPT_DIR/../flake.lock"
SYSTEM="$(nix eval --raw --impure --expr 'builtins.currentSystem')"
POPULATE=false

if [[ "${1:-}" == "--populate" ]] || [[ "${1:-}" == "-p" ]]; then
  POPULATE=true
fi

root_nixpkgs="$(jq -c '.nodes.nixpkgs' "$ROOT_LOCK")"
root_ref="$(jq -r '.nodes.nixpkgs.original | "\(.type):\(.owner)/\(.repo)/\(.ref)"' "$ROOT_LOCK")"

while IFS= read -r -d '' flake; do
  dir="$(dirname "$flake")"
  echo "==> $dir"

  if ! grep -q "nixpkgs.url = \"$root_ref\"" "$flake"; then
    echo "    SKIP: nixpkgs input is not $root_ref" >&2
    continue
  fi

  # Refresh the other inputs (flake-utils, ...), then replace nixpkgs with the
  # root's locked node.
  nix flake update --flake "$dir"
  tmp="$(mktemp "$dir/flake.lock.XXXXXX")"
  jq --argjson np "$root_nixpkgs" '.nodes.nixpkgs = $np' "$dir/flake.lock" >"$tmp"
  mv "$tmp" "$dir/flake.lock"
  echo "    nixpkgs -> $(jq -r '.nodes.nixpkgs.locked.rev' "$dir/flake.lock")"

  if $POPULATE; then
    echo -n "    Pre-building devShell... "
    if nix eval "$dir#devShells.$SYSTEM.default" --apply 'x: "ok"' &>/dev/null; then
      if nix develop "$dir" --command bash -c 'exit 0' 2>/dev/null; then
        echo "done."
      else
        echo "FAILED"
      fi
    else
      echo "SKIP (no devShell for $SYSTEM)"
    fi
  fi
  echo
done < <(find "$SCRIPT_DIR" -name flake.nix -print0)
