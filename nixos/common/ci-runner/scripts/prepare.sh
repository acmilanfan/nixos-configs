#!/usr/bin/env bash
set -euo pipefail

template=${1:?runner template path}
output=${2:?runner config output path}
credentials=${CREDENTIALS_DIRECTORY:?systemd credentials directory}
env_file="$credentials/runner-env"

if [ ! -f "$env_file" ]; then
  printf 'runner credential file is missing\n' >&2
  exit 2
fi

set -a
# shellcheck disable=SC1090
. "$env_file"
set +a

runner_token_re='^(glrt|glrtr)-((t[1-3]_)?[A-Za-z0-9_-]{20}|[A-Za-z0-9_-]{27,300}\.[0-9a-z]{2}\.[0-9a-z]{9})$'
for name in BACKEND_TOKEN FRONTEND_TOKEN; do
  value=${!name:-}
  value=${value%$'\r'}
  if [[ ! "$value" =~ $runner_token_re ]]; then
    printf '%s is not a valid GitLab runner token (glrt-/glrtr-)\n' "$name" >&2
    exit 2
  fi
done

if [ ! -f "$template" ]; then
  printf 'runner template is missing\n' >&2
  exit 2
fi

umask 077
mkdir -p "$(dirname "$output")"
tmp=$(mktemp "$(dirname "$output")/.config.XXXXXX")
cleanup() { rm -f "$tmp"; }
trap cleanup EXIT

sed \
  -e "s|__BACKEND_TOKEN__|$BACKEND_TOKEN|g" \
  -e "s|__FRONTEND_TOKEN__|$FRONTEND_TOKEN|g" \
  "$template" > "$tmp"
chmod 600 "$tmp"
mv -f "$tmp" "$output"
trap - EXIT
