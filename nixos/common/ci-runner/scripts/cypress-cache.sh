#!/usr/bin/env bash
set -euo pipefail

source=${WEEKENDUO_CI_CYPRESS_SOURCE:?Cypress source directory}
cache=${WEEKENDUO_CI_CYPRESS_CACHE:?Cypress cache directory}
marker="$cache/.source"

if [ -e "$cache" ]; then
  # The Nix source tree is read-only. A previous copy can therefore contain
  # read-only directories that block rm; make the owned cache writable first.
  chmod -R u+w "$cache" 2>/dev/null || true
fi

if [ ! -f "$cache/Cypress" ] || [ "$(cat "$marker" 2>/dev/null || true)" != "$source" ]; then
  rm -rf "$cache"
  mkdir -p "$cache"
  cp -a "$source/." "$cache/"
  chmod -R u+w "$cache"
  printf '%s\n' "$source" > "$marker"
fi

printf '{"verified": true}\n' > "$cache/binary_state.json"
