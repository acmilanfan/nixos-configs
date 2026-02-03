#!/bin/bash

# Get power consumption from macmon
POWER_JSON=$(macmon pipe 2>/dev/null | head -1)

if [ -n "$POWER_JSON" ]; then
  # Extract system power (total power draw)
  SYS_POWER=$(echo "$POWER_JSON" | jq -r '.sys_power // 0' 2>/dev/null)

  if [ -n "$SYS_POWER" ] && [ "$SYS_POWER" != "null" ]; then
    # Round to 1 decimal place
    POWER_DISPLAY=$(printf "%.1f" "$SYS_POWER")

    # Color based on power consumption
    if (( $(echo "$SYS_POWER > 30" | bc -l) )); then
      COLOR="0xfff7768e"  # Red - high power
    elif (( $(echo "$SYS_POWER > 15" | bc -l) )); then
      COLOR="0xffe0af68"  # Yellow - medium power
    else
      COLOR="0xff9ece6a"  # Green - low power
    fi

    sketchybar --set $NAME label="${POWER_DISPLAY}W" icon.color="$COLOR"
  else
    sketchybar --set $NAME label="--W"
  fi
else
  sketchybar --set $NAME label="--W"
fi
