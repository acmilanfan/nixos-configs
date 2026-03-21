#!/bin/bash

# Get CPU usage: from $CPU variable if triggered by system_info_update,
# or from top as fallback.
if [ -n "$CPU" ]; then
  CPU_LOAD=$CPU
else
  # Fallback if not triggered by event (e.g., initial load or update_freq)
  CPU_LOAD=$(top -l 1 -n 0 | grep -E "^CPU" | awk '{ print int($3 + $5) }')
fi

# Ensure we have a valid number
if [ -z "$CPU_LOAD" ] || [ "$CPU_LOAD" == "null" ]; then
  CPU_LOAD=0
fi

# Color based on load
if (( $(echo "$CPU_LOAD >= 80" | bc -l) )); then
  COLOR="0xfff7768e"  # Critical red
elif (( $(echo "$CPU_LOAD >= 50" | bc -l) )); then
  COLOR="0xffe0af68"  # Warning yellow
else
  COLOR="0xff7aa2f7"  # Normal blue
fi

# Round for display
CPU_DISPLAY=$(printf "%.0f" "$CPU_LOAD")

# Push value to graph (0.0 to 1.0 scale) and update label
sketchybar --push cpu_graph $(echo "scale=2; $CPU_LOAD / 100" | bc) \
           --set cpu_graph label="${CPU_DISPLAY}%" icon.color="$COLOR"
