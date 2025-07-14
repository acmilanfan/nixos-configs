#!/bin/bash

# AeroSpace integration plugin

source "$CONFIG_DIR/colors.sh"

# Get current workspace
CURRENT_WORKSPACE=$(aerospace list-workspaces --focused)

# Get current layout (simplified)
LAYOUT_INFO=$(aerospace list-windows --workspace focused --format '%{window-id}' | wc -l | xargs)

if [ "$LAYOUT_INFO" -gt 1 ]; then
  LAYOUT="Tiled"
else
  LAYOUT="Single"
fi

sketchybar --set $NAME label="WS:$CURRENT_WORKSPACE $LAYOUT"

