#!/bin/bash

# Network plugin

source "$CONFIG_DIR/colors.sh"

WIFI_STATUS=$(networksetup -getairportnetwork en0 | cut -d: -f2 | xargs)

if [ "$WIFI_STATUS" = "You are not associated with an AirPort network" ]; then
  ICON="$WIFI_DISCONNECTED"
  LABEL="Disconnected"
else
  ICON="$WIFI_CONNECTED"
  LABEL="$WIFI_STATUS"
fi

sketchybar --set $NAME icon="$ICON" label="$LABEL"

