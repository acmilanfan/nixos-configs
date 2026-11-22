#!/usr/bin/env bash
set -euo pipefail
script=$(dirname "$0")/../hypr-power-watts
export FIXTURE; FIXTURE=$(mktemp -d "$HOME/ai/artifacts/nixos-configs/quickshell-shell/power.XXXXXX" 2>/dev/null || mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
export HYPR_BAT_PATH="$FIXTURE/bat"
mkdir -p "$HYPR_BAT_PATH"
printf '16664000\n' > "$HYPR_BAT_PATH/power_now"
bash "$script" | jq -e '.text == "󱐋 16.7W" and .class == "medium"' >/dev/null
printf '42000000\n' > "$HYPR_BAT_PATH/power_now"
bash "$script" | jq -e '.text == "󱐋 42.0W" and .class == "high"' >/dev/null
rm "$HYPR_BAT_PATH/power_now"
bash "$script" | jq -e '.text == "󱐋 --W" and .class == "none"' >/dev/null
echo 'hypr-power-watts: all cases passed'
