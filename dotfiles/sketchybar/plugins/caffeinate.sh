#!/bin/bash

# The persistent system-sleep setting and Hammerspoon's display-idle setting
# are separate indicators. Query the former at startup, on events and every
# 30 seconds so terminal changes, reboots and reloads cannot leave stale state.
if [ "$NAME" = "no_sleep" ]; then
  source "$CONFIG_DIR/colors.sh"
  if ! mode=$(/run/current-system/sw/bin/no-sleep state 2>/dev/null); then
    sketchybar --set "$NAME" icon.color="$WARNING_COLOR" label="LID ?" \
               label.color="$WARNING_COLOR" label.drawing=on
    exit 1
  fi
  if [ "$mode" = "on" ]; then
    sketchybar --set "$NAME" icon.color="$WARNING_COLOR" label="LID" \
               label.color="$WARNING_COLOR" label.drawing=on
  else
    sketchybar --set "$NAME" icon.color="$INACTIVE_COLOR" label.drawing=off
  fi
  exit 0
fi

if [ "$SENDER" = "nanowm_caffeinate" ]; then
  if [ "$STATE" = "on" ]; then
    sketchybar --set $NAME drawing=on
  else
    sketchybar --set $NAME drawing=off
  fi
fi
