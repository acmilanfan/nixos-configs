#!/usr/bin/env bash
set -euo pipefail

path=${1:?filesystem path}
min_gb=${2:?minimum free GB}

if [[ ! "$min_gb" =~ ^[0-9]+$ ]]; then
  printf 'minimum free GB must be an integer\n' >&2
  exit 2
fi

avail_kb=$(df -Pk "$path" | awk 'NR == 2 { print $4 }')
avail_gb=$((avail_kb / 1024 / 1024))

if ((avail_gb < min_gb)); then
  printf 'CI disk guard: %s has %s GB free; %s GB required\n' "$path" "$avail_gb" "$min_gb" >&2
  exit 1
fi
