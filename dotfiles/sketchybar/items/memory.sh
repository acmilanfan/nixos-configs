#!/bin/bash

# Memory widget matching AwesomeWM's ram widget

sketchybar --add item memory right \
           --set memory icon=$MEMORY \
                        icon.color=$MEMORY_COLOR \
                        label.color=$LABEL_COLOR \
                        update_freq=30 \
                        script="$PLUGIN_DIR/memory.sh"

