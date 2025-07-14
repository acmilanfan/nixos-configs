#!/bin/bash

# Calendar plugin matching AwesomeWM's textclock

source "$CONFIG_DIR/colors.sh"

sketchybar --set $NAME icon="$CALENDAR" \
                   label="$(date '+%a %b %d  %I:%M %p')"

