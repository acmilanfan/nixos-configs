#!/bin/bash

# Battery widget matching AwesomeWM's batteryarc widget

sketchybar --add item battery right \
           --set battery script="$PLUGIN_DIR/battery.sh" \
                        icon.color=$BATTERY_COLOR \
                        label.color=$LABEL_COLOR \
                        update_freq=120 \
           --subscribe battery system_woke power_source_change

