#!/bin/bash

# Calendar widget matching AwesomeWM's textclock
# Shows current date and time

sketchybar --add item calendar right \
           --set calendar icon=$CALENDAR \
                         icon.color=$BLUE \
                         label.color=$LABEL_COLOR \
                         update_freq=30 \
                         script="$PLUGIN_DIR/calendar.sh" \
                         click_script="$PLUGIN_DIR/zen.sh"

