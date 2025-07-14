#!/bin/bash

# Network widget

sketchybar --add item network right \
           --set network icon=$NETWORK \
                         icon.color=$CYAN \
                         label.color=$LABEL_COLOR \
                         update_freq=10 \
                         script="$PLUGIN_DIR/network.sh"

