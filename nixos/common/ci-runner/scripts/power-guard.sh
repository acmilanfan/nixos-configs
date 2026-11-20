#!/usr/bin/env bash
set -euo pipefail

min_percent=${1:?minimum battery percent}
power_supply=${WEEKENDUO_CI_POWER_SUPPLY:-/sys/class/power_supply}

if [[ ! "$min_percent" =~ ^[0-9]+$ ]]; then
  printf 'minimum battery percent must be an integer\n' >&2
  exit 2
fi

shopt -s nullglob
on_ac=false
for online in "$power_supply"/AC*/online; do
  if [ "$(cat "$online")" = "1" ]; then
    on_ac=true
    break
  fi
done

if [ "$on_ac" = true ]; then
  exit 0
fi

capacity=
for file in "$power_supply"/BAT*/capacity; do
  capacity=$(cat "$file")
  break
done

# A host without a battery (or without a readable battery) has no battery
# policy to enforce; the scheduled-full check is for laptops.
if [ -z "$capacity" ]; then
  exit 0
fi

if [[ ! "$capacity" =~ ^[0-9]+$ ]] || ((capacity < min_percent)); then
  printf 'CI power guard: battery %s%% below %s%% and not on AC\n' "$capacity" "$min_percent" >&2
  exit 1
fi
