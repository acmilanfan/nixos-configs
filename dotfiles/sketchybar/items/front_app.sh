#!/bin/bash

# Front app configuration matching AwesomeWM's tasklist
# Shows the currently focused application

sketchybar --add item front_app center \
           --set front_app       background.color=$BACKGROUND_1 \
                                 background.border_color=$BACKGROUND_2 \
                                 icon.color=$BLUE \
                                 icon.font="sketchybar-app-font:Regular:16.0" \
                                 label.color=$LABEL_COLOR \
                                 label.font="$FONT:Black:12.0" \
                                 script="$PLUGIN_DIR/front_app.sh" \
           --subscribe front_app front_app_switched

