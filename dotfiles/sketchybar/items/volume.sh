#!/bin/bash

# Volume widget matching AwesomeWM's volume widget

sketchybar --add item volume right \
           --set volume script="$PLUGIN_DIR/volume.sh" \
                        icon.color=$VOLUME_COLOR \
                        label.color=$LABEL_COLOR \
           --subscribe volume volume_change

