#!/bin/bash

# System Info Daemon for SketchyBar
# Uses macmon pipe for efficient, event-driven updates on Apple Silicon

# Default update interval in milliseconds (e.g., 2000ms = 2s)
INTERVAL=${1:-2000}

# Start macmon pipe
macmon pipe --interval "$INTERVAL" | while read -r line; do
  # Extract metrics using jq
  CPU_P=$(echo "$line" | jq -r '.pcpu_usage[1] // 0')
  CPU_E=$(echo "$line" | jq -r '.ecpu_usage[1] // 0')
  # Simple sum of percentages (normalized to 0-100)
  # Note: On some systems this might exceed 100 if not normalized,
  # but macmon percentages are usually 0.0 to 1.0.
  CPU=$(echo "($CPU_P + CPU_E) * 100" | bc)

  # Get memory pressure (more accurate on macOS than raw used RAM)
  MEM=$(memory_pressure 2>/dev/null | grep "System-wide memory free percentage" | awk '{print 100 - $5}' | tr -d '%')

  POWER=$(echo "$line" | jq -r '.sys_power // 0')
  # Trigger sketchybar event with variables
  sketchybar --trigger system_info_update \
             CPU="$CPU" \
             MEM="$MEM" \
             POWER="$POWER"
done
