#!/bin/bash

# Space plugin for workspace management
# Matches AwesomeWM tag behavior

source "$CONFIG_DIR/colors.sh"

if [ "$SELECTED" = "true" ]; then
  sketchybar --set $NAME background.drawing=on \
                   background.color=$SPACE_ACTIVE \
                   label.color=$BAR_COLOR \
                   icon.color=$BAR_COLOR
else
  sketchybar --set $NAME background.drawing=off \
                   label.color=$SPACE_INACTIVE \
                   icon.color=$SPACE_INACTIVE
fi

