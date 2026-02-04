#!/bin/bash

VOL=$(osascript -e "output volume of (get volume settings)")
MUTED=$(osascript -e "output muted of (get volume settings)")

if [[ $MUTED != "false" ]]; then
  ICON="󰝟"
  COLOR="0xff565f89"
elif [[ $VOL -ge 66 ]]; then
  ICON="󰕾"
  COLOR="0xff7aa2f7"
elif [[ $VOL -ge 33 ]]; then
  ICON="󰖀"
  COLOR="0xff7aa2f7"
elif [[ $VOL -ge 1 ]]; then
  ICON="󰕿"
  COLOR="0xff7aa2f7"
else
  ICON="󰝟"
  COLOR="0xff565f89"
fi
sketchybar --set $NAME icon="$ICON" icon.color="$COLOR" label="$VOL%"
