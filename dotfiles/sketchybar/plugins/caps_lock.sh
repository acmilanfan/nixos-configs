#!/bin/bash

# The STATE variable is passed from Hammerspoon via the event trigger
# e.g., sketchybar --trigger caps_lock_update STATE=on/off
# If it's missing (e.g., on sketchybar reload), ask Hammerspoon to send it: nanowm's URL
# handler re-triggers caps_lock_update with STATE set (rather than a blocking `hs -c`).

if [ -z "$STATE" ]; then
  if pgrep -x Hammerspoon >/dev/null; then
    /usr/bin/open -g "hammerspoon://nanowm?cmd=capsLock"
  fi
  exit 0
fi

if [ "$STATE" = "on" ]; then
  sketchybar --set "$NAME" drawing=on
else
  sketchybar --set "$NAME" drawing=off
fi
