#!/bin/bash

# Volume widget (based on FelixKratz defaults)

volume=(
  script="$PLUGIN_DIR/volume.sh"
  padding_left=3
  padding_right=3
  icon.font="$FONT:Regular:14.0"
  label.drawing=on
)

sketchybar --add item volume right \
           --set volume "${volume[@]}" \
           --subscribe volume volume_change

