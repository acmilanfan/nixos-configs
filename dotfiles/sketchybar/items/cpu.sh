#!/bin/bash

# CPU widget matching AwesomeWM's cpu widget

sketchybar --add item cpu right \
           --set cpu icon=$CPU \
                     icon.color=$CPU_COLOR \
                     label.color=$LABEL_COLOR \
                     update_freq=2 \
                     script="$PLUGIN_DIR/cpu.sh"

