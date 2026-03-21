#!/bin/bash

if [ "$SENDER" = "nanowm_update" ]; then
  DRAWING="on"
  ICON=""
  BG_DRAWING="on"

  # Check Fullscreen first (highest priority)
  if [ "$FULLSCREEN" = "1" ]; then
    ICON="󰊓"
  elif [ "$LAYOUT" = "mono" ]; then
    ICON="󰍉"
  elif [ "$LAYOUT" = "horizontal" ]; then
    ICON="󰗛"
  elif [ "$LAYOUT" = "scrolling" ]; then
    ICON="󰖲"
  else # Default to vertical
    ICON="󰗚"
  fi

  sketchybar --set $NAME drawing=$DRAWING \
                         background.drawing=$BG_DRAWING \
                         icon="$ICON"
fi
