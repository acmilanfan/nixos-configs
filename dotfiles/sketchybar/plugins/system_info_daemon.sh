#!/bin/bash

# System Info Daemon for SketchyBar
# Uses macmon pipe for efficient, event-driven updates on Apple Silicon

# Default update interval in milliseconds (e.g., 2000ms = 2s)
INTERVAL=${1:-4000}

# macmon reports each cluster's load as its own 0-1 fraction, so the total is
# their average weighted by core count (adding them gave 0-200%).
P_CORES=$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || echo 1)
E_CORES=$(sysctl -n hw.perflevel1.logicalcpu 2>/dev/null || echo 0)

# Start macmon pipe
macmon pipe --interval "$INTERVAL" | while read -r line; do
  # Single jq call extracts CPU and power, does the math internally
  read -r CPU POWER <<< "$(echo "$line" | jq -r --argjson p "${P_CORES:-1}" --argjson e "${E_CORES:-0}" '
    [((.pcpu_usage[1] // 0) * $p + (.ecpu_usage[1] // 0) * $e) / ([$p + $e, 1] | max) * 100,
     .sys_power // 0]
    | map(tostring) | join(" ")
  ')"

  # Use memory_pressure command (same kernel source as the standalone memory.sh plugin)
  MEM=$(memory_pressure 2>/dev/null | awk '/System-wide memory free percentage/ {printf "%.0f", 100 - $5}')

  sketchybar --trigger system_info_update \
             CPU="$CPU" \
             MEM="$MEM" \
             POWER="$POWER"
done
