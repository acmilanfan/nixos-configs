#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYSTEM="$(nix eval --raw --impure --expr 'builtins.currentSystem')"
POPULATE=false

if [[ "${1:-}" == "--populate" ]] || [[ "${1:-}" == "-p" ]]; then
  POPULATE=true
fi

while IFS= read -r -d '' flake; do
  dir="$(dirname "$flake")"
  echo "==> Updating $dir"
  nix flake update --flake "$dir"

  if $POPULATE; then
    echo -n "    Pre-building devShell... "
    if nix eval "$dir#devShells.$SYSTEM.default" --apply 'x: "ok"' &>/dev/null; then
      if nix develop "$dir" --command bash -c 'exit 0' 2>/dev/null; then
        echo "done."
      else
        echo "FAILED (likely Linux-only dependencies)"
      fi
    else
      echo "SKIP (no devShell for $SYSTEM)"
    fi
  fi
  echo
done < <(find "$SCRIPT_DIR" -name flake.nix -print0)
