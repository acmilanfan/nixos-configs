#!/bin/bash

# Toggle between power consumption and battery time remaining

# Check current state (stored in a temp file)
STATE_FILE="/tmp/sketchybar_power_state"

if [ -f "$STATE_FILE" ] && [ "$(cat $STATE_FILE)" = "time" ]; then
  # Currently showing time, switch to power
  echo "power" > "$STATE_FILE"

  # Get power from macmon
  POWER_JSON=$(macmon pipe 2>/dev/null | head -1)
  SYS_POWER=$(echo "$POWER_JSON" | jq -r '.sys_power // 0' 2>/dev/null)
  POWER_DISPLAY=$(printf "%.1f" "$SYS_POWER")

  sketchybar --set power icon="󱐋" label="''${POWER_DISPLAY}W"
else
  # Currently showing power (or first click), switch to time
  echo "time" > "$STATE_FILE"

  # Get battery time remaining
  BATT_INFO=$(pmset -g batt)
  TIME_LEFT=$(echo "$BATT_INFO" | grep -o '[0-9]*:[0-9]* remaining' | cut -d' ' -f1)

  if [ -n "$TIME_LEFT" ] && [ "$TIME_LEFT" != "0:00" ]; then
    sketchybar --set power icon="󰔟" label="$TIME_LEFT"
  else
    # Check if charging
    if echo "$BATT_INFO" | grep -q "AC Power"; then
      sketchybar --set power icon="󰂄" label="AC"
    else
      sketchybar --set power icon="󰔟" label="--:--"
    fi
  fi
fi

# Reset back to power after 5 seconds
(sleep 5 && echo "power" > "$STATE_FILE") &
