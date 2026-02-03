#!/bin/bash

if [ "$SENDER" = "nanowm_update" ]; then
  if [ -n "$TIMER" ] && [ "$TIMER" != "" ]; then
    sketchybar --set $NAME drawing=on background.drawing=on label="$TIMER"
  else
    sketchybar --set $NAME drawing=off background.drawing=off
  fi
fi
