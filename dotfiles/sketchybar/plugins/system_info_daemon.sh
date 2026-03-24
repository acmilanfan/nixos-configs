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

  # Use vm_stat instead of memory_pressure (much lighter)
  MEM=$(vm_stat 2>/dev/null | awk '/Pages active/ {active=$3} /Pages wired/ {wired=$4} /Pages free/ {free=$3} /Pages speculative/ {spec=$3} END {
    gsub(/\./,"",active); gsub(/\./,"",wired); gsub(/\./,"",free); gsub(/\./,"",spec)
    used = (active + wired) * 4096
    total = (active + wired + free + spec) * 4096
    if (total > 0) printf "%.0f", (used / total) * 100
  }')

  sketchybar --trigger system_info_update \
             CPU="$CPU" \
             MEM="$MEM" \
             POWER="$POWER"
done
