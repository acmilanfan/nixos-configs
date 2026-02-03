#!/bin/bash

# Get CPU usage using top (fast, instant)
CPU_LOAD=$(top -l 1 -n 0 | grep -E "^CPU" | awk '{ print int($3 + $5) }')

# Fallback if top fails
if [ -z "$CPU_LOAD" ] || [ "$CPU_LOAD" -lt 0 ] 2>/dev/null; then
  CPU_LOAD=$(top -l 1 -n 0 | grep -E "^CPU" | awk '{ print int($3 + $5) }')
fi

# Ensure we have a valid number
if [ -z "$CPU_LOAD" ]; then
  CPU_LOAD=0
fi

# Color based on load
if [[ $CPU_LOAD -ge 80 ]]; then
  COLOR="0xfff7768e"  # Critical red
elif [[ $CPU_LOAD -ge 50 ]]; then
  COLOR="0xffe0af68"  # Warning yellow
else
  COLOR="0xff7aa2f7"  # Normal blue
fi

# Push value to graph (0.0 to 1.0 scale) and update label
sketchybar --push cpu_graph $(echo "scale=2; $CPU_LOAD / 100" | bc) \
           --set cpu_graph label="$CPU_LOAD%" icon.color="$COLOR"
