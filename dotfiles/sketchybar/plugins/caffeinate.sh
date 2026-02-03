#!/bin/bash

if [ "$SENDER" = "nanowm_caffeinate" ]; then
  if [ "$STATE" = "on" ]; then
    sketchybar --set $NAME drawing=on
  else
    sketchybar --set $NAME drawing=off
  fi
fi
