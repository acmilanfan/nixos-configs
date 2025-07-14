#!/bin/bash

# Volume plugin matching AwesomeWM's volume widget

source "$CONFIG_DIR/colors.sh"

VOLUME=$(osascript -e "output volume of (get volume settings)")\nMUTE=$(osascript -e "output muted of (get volume settings)")

if [[ $MUTE != "false" ]]; then
  ICON="$VOLUME_0"
  LABEL="Muted"
else
  case ${VOLUME} in
    [6-9][0-9]|100) ICON="$VOLUME_100"
    ;;
    [3-5][0-9]) ICON="$VOLUME_66"
    ;;
    [1-2][0-9]) ICON="$VOLUME_33"
    ;;
    [1-9]) ICON="$VOLUME_10"
    ;;
    0) ICON="$VOLUME_0"
    ;;
  esac
  LABEL="$VOLUME%"
fi

sketchybar --set $NAME icon="$ICON" label="$LABEL"

