#!/bin/bash

FIRST_SCREEN_BRIGHTNESS="/sys/class/backlight/card1-eDP-2-backlight/brightness"
SECOND_SCREEN_BRIGHTNESS="/sys/class/backlight/intel_backlight/brightness"
BRIGHTNESS=$(cat "$FIRST_SCREEN_BRIGHTNESS")

echo "$BRIGHTNESS" | sudo tee "$SECOND_SCREEN_BRIGHTNESS"
