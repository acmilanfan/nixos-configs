#!/bin/bash

PERCENTAGE=$(pmset -g batt | grep -o "[0-9]\{1,3\}%" | tr -d "%")
CHARGING=$(pmset -g batt | grep 'AC Power')

if [ "$PERCENTAGE" = "" ]; then exit 0; fi

if [[ $CHARGING != "" ]]; then
  ICON="󰂄"
  COLOR="0xff9ece6a"  # Green when charging
elif [[ $PERCENTAGE -ge 80 ]]; then
  ICON="󰁹"
  COLOR="0xff9ece6a"  # Green
elif [[ $PERCENTAGE -ge 60 ]]; then
  ICON="󰂁"
  COLOR="0xff7aa2f7"  # Blue
elif [[ $PERCENTAGE -ge 40 ]]; then
  ICON="󰁿"
  COLOR="0xff7aa2f7"  # Blue
elif [[ $PERCENTAGE -ge 20 ]]; then
  ICON="󰁻"
  COLOR="0xffe0af68"  # Yellow warning
else
  ICON="󰂃"
  COLOR="0xfff7768e"  # Red critical
fi

sketchybar --set $NAME icon="$ICON" icon.color="$COLOR" label="$PERCENTAGE%"
