#!/usr/bin/env bash
set -euo pipefail

source=${WEEKENDUO_CI_CYPRESS_SOURCE:?Cypress source directory}
cache=${WEEKENDUO_CI_CYPRESS_CACHE:?Cypress cache directory}
marker="$cache/.source"

if [ ! -f "$cache/Cypress" ] || [ "$(cat "$marker" 2>/dev/null || true)" != "$source" ]; then
  rm -rf "$cache"
  mkdir -p "$cache"
  cp -a "$source/." "$cache/"
  printf '%s\n' "$source" > "$marker"
fi

printf '{"verified": true}\n' > "$cache/binary_state.json"
