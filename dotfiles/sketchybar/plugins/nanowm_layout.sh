#!/bin/bash

if [ "$SENDER" = "nanowm_update" ]; then
  LABEL=""
  DRAWING="off"
  ICON=""
  BG_DRAWING="off"

  # Check Fullscreen first (highest priority)
  if [ "$FULLSCREEN" = "1" ]; then
    LABEL="Full"
    DRAWING="on"
    BG_DRAWING="on"
    ICON="󰊓"
  # Check Monocle
  elif [ "$LAYOUT" = "monocle" ]; then
    LABEL="Mono"
    DRAWING="on"
    BG_DRAWING="on"
    ICON="󰊓"
  fi

  sketchybar --set $NAME drawing=$DRAWING \
                         background.drawing=$BG_DRAWING \
                         label="$LABEL" \
                         icon="$ICON"
fi
