#!/bin/bash

# System Info Daemon for SketchyBar
# Uses macmon pipe for efficient, event-driven updates on Apple Silicon

# Default update interval in milliseconds (e.g., 2000ms = 2s)
INTERVAL=${1:-2000}

# Start macmon pipe
macmon pipe --interval "$INTERVAL" | while read -r line; do
  # Single jq call extracts CPU and power, does the math internally
  read -r CPU POWER <<< $(echo "$line" | jq -r '
    [((.pcpu_usage[1] // 0) + (.ecpu_usage[1] // 0)) * 100, .sys_power // 0]
    | map(tostring) | join(" ")
  ')

  # Use memory_pressure command (same kernel source as the standalone memory.sh plugin)
  MEM=$(memory_pressure 2>/dev/null | awk '/System-wide memory free percentage/ {printf "%.0f", 100 - $5}')

  sketchybar --trigger system_info_update \
             CPU="$CPU" \
             MEM="$MEM" \
             POWER="$POWER"
done
