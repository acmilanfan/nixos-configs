#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  printf 'Run as root: sudo weekenduo-ci-set-tokens\n' >&2
  exit 2
fi

prompt_token() {
  local label=$1 value
  while true; do
    read -rsp "$label: " value
    printf '\n' >&2
    if [[ "$value" =~ ^glrt-[A-Za-z0-9_-]+$ ]]; then
      printf '%s' "$value"
      return 0
    fi
    printf 'Token must start with glrt- and use only letters, digits, _ or -.\n' >&2
  done
}

backend=$(prompt_token 'Backend runner token (glrt-...)')
frontend=$(prompt_token 'Frontend runner token (glrt-...)')

install -d -m 0750 -o root -g root /etc/weekenduo-ci
umask 077
tmp=$(mktemp /etc/weekenduo-ci/.runner.env.XXXXXX)
cleanup() { rm -f "$tmp"; }
trap cleanup EXIT

printf 'BACKEND_TOKEN=%s\nFRONTEND_TOKEN=%s\n' "$backend" "$frontend" > "$tmp"
chown root:root "$tmp"
chmod 600 "$tmp"
mv -f "$tmp" /etc/weekenduo-ci/runner.env
trap - EXIT
unset backend frontend

printf 'Installed /etc/weekenduo-ci/runner.env\n' >&2
systemctl restart weekenduo-ci-runner
printf 'Restarted weekenduo-ci-runner; inspect with: systemctl status weekenduo-ci-runner\n' >&2
