#!/bin/bash

# Space plugin for workspace management (based on FelixKratz defaults)

source "$CONFIG_DIR/colors.sh"

if [ "$SELECTED" = "true" ]; then
  sketchybar --set $NAME background.drawing=on \
                   background.color=$WHITE \
                   icon.color=$BLACK
else
  sketchybar --set $NAME background.drawing=off \
                   icon.color=$WHITE
fi

