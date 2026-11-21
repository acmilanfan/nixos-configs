#!/usr/bin/env bash
set -euo pipefail

source=${WEEKENDUO_CI_CYPRESS_SOURCE:?Cypress source directory}
cache=${WEEKENDUO_CI_CYPRESS_CACHE:?Cypress cache directory}

mkdir -p "$cache"
if [ ! -f "$cache/Cypress" ]; then
  install -m 0755 "$source/Cypress" "$cache/Cypress"
fi
ln -sfn "$source/resources" "$cache/resources"
printf '{"verified": true}\n' > "$cache/binary_state.json"
