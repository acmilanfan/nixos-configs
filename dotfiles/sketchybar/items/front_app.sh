#!/bin/bash

# Front app configuration (based on FelixKratz defaults)
# Shows the currently focused application

front_app=(
  icon.drawing=off
  label.font="$FONT:Black:12.0"
  label.padding_right=15
  label.padding_left=0
  padding_right=15
  padding_left=15
  script="$PLUGIN_DIR/front_app.sh"
  click_script="open -a 'Mission Control'"
)

sketchybar --add item front_app center \
           --set front_app "${front_app[@]}" \
           --subscribe front_app front_app_switched

