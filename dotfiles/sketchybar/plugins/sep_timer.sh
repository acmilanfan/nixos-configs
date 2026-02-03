#!/bin/bash

if [ "$SENDER" = "nanowm_update" ]; then
  if [ -n "$TIMER" ] && [ "$TIMER" != "" ]; then
    sketchybar --set $NAME drawing=on
  else
    sketchybar --set $NAME drawing=off
  fi
fi
