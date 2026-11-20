#!/usr/bin/env bash
set -euo pipefail

ci_home=${HOME:?CI home}
config_dir="$ci_home/.config/weekenduo-ci"
umask 077
mkdir -p "$config_dir"
chmod 700 "$config_dir"

daemon_id=$(docker info --format '{{.ID}}')
if [[ ! "$daemon_id" =~ ^[a-f0-9]{12,64}$ ]]; then
  printf 'Docker daemon ID is not valid\n' >&2
  exit 1
fi

tmp=$(mktemp "$config_dir/.runtime.XXXXXX")
cleanup() { rm -f "$tmp"; }
trap cleanup EXIT

printf '{\n  "user": "%s",\n  "home": "%s",\n  "dockerSocket": "/var/run/docker.sock",\n  "dockerId": "%s",\n  "buildRoot": "%s/ci-builds",\n  "artifactRoot": "%s/ai/artifacts"\n}\n' \
  "$(id -un)" "$ci_home" "$daemon_id" "$ci_home" "$ci_home" > "$tmp"
chmod 600 "$tmp"
mv -f "$tmp" "$config_dir/runtime.json"
trap - EXIT
