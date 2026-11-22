#!/usr/bin/env bash
set -euo pipefail

local_only=0
watch=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --local) local_only=1 ;;
    --watch|-w) watch=1 ;;
    --help|-h)
      printf 'Usage: ci-status [--local] [--watch]\n'
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
  shift
done

show() {
  printf 'Weekenduo CI — %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"

  printf 'Runner: '
  if systemctl is-active --quiet weekenduo-ci-runner; then
    printf 'active since %s\n' "$(systemctl show weekenduo-ci-runner -p ActiveEnterTimestamp --value)"
  else
    printf 'inactive\n'
  fi

  printf '\nActive CI processes:\n'
  # Command lines can contain per-run cron secrets and Supabase keys; show
  # only the process name, never argv.
  ps -u weekenduo-ci -o pid=,etime=,comm= 2>/dev/null |
    awk '$3 != "gitlab-runner" && $3 != "grep"' |
    sed 's/^/  /' || true

  printf '\nLane ports:\n'
  ss -ltnH 2>/dev/null |
    awk '{print $4}' |
    grep -E ':(3000|3100|18080|18180|5532[0-9]|5533[0-9])$' |
    sed 's/^/  /' || printf '  none\n'

  printf '\nRecent runner events:\n'
  journalctl -u weekenduo-ci-runner -n 120 -o cat --no-pager 2>/dev/null |
    grep -E 'Added job to processing list|Job succeeded|Job failed' |
    tail -8 |
    sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g' |
    cut -c1-180 |
    sed 's/^/  /' || printf '  none\n'

  if [ "$local_only" -eq 0 ]; then
    for repo in weekenduo/backend weekenduo/duomobile; do
      printf '\nGitLab — %s:\n' "$repo"
      if output=$(glab ci list -R "$repo" -F json -P 4 2>/dev/null); then
        if printf '%s' "$output" | jq -e 'length > 0' >/dev/null 2>&1; then
          printf '%s' "$output" |
            jq -r '.[] | [.id, .status, .ref, .source] | @tsv' |
            while IFS=$'\t' read -r id status ref source; do
              printf '  %-12s %-22s %-38s %s\n' "$id" "$status" "$ref" "$source"
            done
        else
          printf '  no pipelines\n'
        fi
      else
        printf '  glab unavailable or not authenticated\n'
      fi
    done
  fi
}

if [ "$watch" -eq 1 ]; then
  while true; do
    printf '\033c'
    show
    sleep 10
  done
else
  show
fi
