#!/bin/bash

if [ "$SENDER" = "front_app_switched" ]; then
  sketchybar --set $NAME label="$INFO" icon.background.image="app.$INFO"
fi

if [ "$SENDER" = "nanowm_update" ]; then
  INDICATOR=""
  if [ "$IS_FLOATING" = "1" ]; then
    INDICATOR=" 󱂬"
  fi
  sketchybar --set $NAME label="$APP$INDICATOR" icon.background.image="app.$APP"
fi
