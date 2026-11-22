#!/usr/bin/env bash
set -euo pipefail

notify_line() {
  local line=$1 project job duration status urgency title body

  line=$(printf '%s' "$line" | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g')

  case "$line" in
    *"Job failed"*) status=failed; urgency=critical ;;
    *"Job succeeded"*) status=succeeded; urgency=normal ;;
    *) return 0 ;;
  esac

  if [ "$status" = succeeded ] && [ "${CI_NOTIFY_SUCCESS:-0}" != "1" ]; then
    return 0
  fi

  project=${line#*project_full_path=}
  project=${project%% *}
  job=${line#* job=}
  job=${job%% *}
  duration=${line#*duration_s=}
  duration=${duration%% *}

  [ -n "$project" ] || project=unknown
  [ -n "$job" ] || job=unknown
  [ -n "$duration" ] || duration=unknown

  title="Weekenduo CI: ${project#weekenduo/} $status"
  body="Job $job ${status} in ${duration}s"
  if [ "$status" = failed ]; then
    body="$body
https://gitlab.com/$project/-/jobs/$job"
  fi

  if [ "${CI_NOTIFY_DRY_RUN:-0}" = "1" ]; then
    printf '%s: %s\n' "$title" "$body"
    return 0
  fi

  notify-send -a "Weekenduo CI" -u "$urgency" "$title" "$body" || true
}

if [ "${1:-}" = "--parse" ]; then
  shift
  notify_line "${1:-}"
  exit 0
fi

journalctl -u weekenduo-ci-runner -f -o cat --since now |
  while IFS= read -r line; do
    notify_line "$line"
  done
