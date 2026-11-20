#!/usr/bin/env bash
set -euo pipefail

ci_home=${WEEKENDUO_CI_HOME:?CI home}
min_free_gb=${WEEKENDUO_CI_MIN_FREE_GB:-20}
battery_min=${WEEKENDUO_CI_BATTERY_MIN:-30}

weekenduo-ci-disk-guard "$ci_home" "$min_free_gb"

for attempt in $(seq 1 30); do
  if docker info >/dev/null 2>&1; then
    break
  fi
  if [ "$attempt" -eq 30 ]; then
    printf 'CI Docker daemon is unavailable\n' >&2
    exit 1
  fi
  sleep 1
done

if [ "${CI_PIPELINE_SOURCE:-}" = "schedule" ] && [ "${WD_CI_E2E:-}" = "full" ]; then
  weekenduo-ci-power-guard "$battery_min"
fi
