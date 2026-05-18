#!/bin/bash

# The STATE variable is passed from Hammerspoon via the event trigger
# e.g., sketchybar --trigger caps_lock_update STATE=on/off
# If it's missing (e.g., on sketchybar reload), we query Hammerspoon directly.

if [ -z "$STATE" ]; then
  STATE_RAW=$(/opt/homebrew/bin/hs -c "print(hs.hid.capslock.get())" 2>/dev/null)
  if [ "$STATE_RAW" = "true" ]; then
    STATE="on"
  else
    STATE="off"
  fi
fi

if [ "$STATE" = "on" ]; then
  sketchybar --set "$NAME" drawing=on
else
  sketchybar --set "$NAME" drawing=off
fi
