#!/bin/bash

# AeroSpace integration widget
# Shows current layout and provides quick actions

sketchybar --add item aerospace right \
           --set aerospace icon="􀢌" \
                          icon.color=$BLUE \
                          label.color=$LABEL_COLOR \
                          script="$PLUGIN_DIR/aerospace.sh" \
                          click_script="aerospace layout tiles accordion" \
                          update_freq=5

