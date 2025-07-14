#!/bin/bash

# Media plugin for music/video controls

source "$CONFIG_DIR/colors.sh"

STATE="$(echo "$INFO" | jq -r '.state')"
if [ "$STATE" = "playing" ]; then
  MEDIA="$(echo "$INFO" | jq -r '.title + " - " + .artist')"
  sketchybar --set $NAME label="$MEDIA" drawing=on
elif [ "$STATE" = "paused" ]; then
  sketchybar --set $NAME label="Paused" drawing=on
else
  sketchybar --set $NAME drawing=off
fi

