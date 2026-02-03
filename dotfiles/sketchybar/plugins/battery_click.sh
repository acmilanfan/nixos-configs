#!/bin/bash

# Toggle between battery percentage and time remaining

STATE_FILE="/tmp/sketchybar_battery_state"

# Get battery info
BATT_INFO=$(pmset -g batt)
PERCENTAGE=$(echo "$BATT_INFO" | grep -o "[0-9]\{1,3\}%" | tr -d "%")
CHARGING=$(echo "$BATT_INFO" | grep "AC Power")
TIME_LEFT=$(echo "$BATT_INFO" | grep -o "[0-9]*:[0-9]* remaining" | cut -d" " -f1)

# Determine icon and color based on state
if [[ $CHARGING != "" ]]; then
  ICON="󰂄"
  COLOR="0xff9ece6a"
elif [[ $PERCENTAGE -ge 80 ]]; then
  ICON="󰁹"
  COLOR="0xff9ece6a"
elif [[ $PERCENTAGE -ge 60 ]]; then
  ICON="󰂁"
  COLOR="0xff7aa2f7"
elif [[ $PERCENTAGE -ge 40 ]]; then
  ICON="󰁿"
  COLOR="0xff7aa2f7"
elif [[ $PERCENTAGE -ge 20 ]]; then
  ICON="󰁻"
  COLOR="0xffe0af68"
else
  ICON="󰂃"
  COLOR="0xfff7768e"
fi

if [ -f "$STATE_FILE" ] && [ "$(cat $STATE_FILE)" = "time" ]; then
  # Currently showing time, switch back to percentage
  echo "percent" > "$STATE_FILE"
  sketchybar --set battery icon="$ICON" icon.color="$COLOR" label="$PERCENTAGE%"
else
  # Currently showing percentage, switch to time
  echo "time" > "$STATE_FILE"

  if [ -n "$TIME_LEFT" ] && [ "$TIME_LEFT" != "0:00" ]; then
    sketchybar --set battery icon="󰔟" icon.color="$COLOR" label="$TIME_LEFT"
  elif [[ $CHARGING != "" ]]; then
    # Charging - show charging time if available
    CHARGE_TIME=$(echo "$BATT_INFO" | grep -o "[0-9]*:[0-9]* until" | cut -d" " -f1)
    if [ -n "$CHARGE_TIME" ]; then
      sketchybar --set battery icon="󰂄" icon.color="$COLOR" label="$CHARGE_TIME"
    else
      sketchybar --set battery icon="󰂄" icon.color="$COLOR" label="Charging"
    fi
  else
    sketchybar --set battery icon="󰔟" icon.color="$COLOR" label="--:--"
  fi
fi
