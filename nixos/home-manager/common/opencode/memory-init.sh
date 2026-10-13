#!/usr/bin/env bash
set -euo pipefail

seeds="$1"
memory="$2"

# These are runtime notes, not Home Manager symlinks into the read-only store.
# A rebuild may fill in a missing block, but must never reset learned content.
umask 077
mkdir -p "$memory"
for seed in "$seeds"/*.md; do
  [ -f "$seed" ] || continue
  target="$memory/${seed##*/}"
  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    (set -o noclobber; cat "$seed" > "$target")
  fi
done
