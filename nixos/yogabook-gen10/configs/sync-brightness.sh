#!/bin/bash
# Copy the eDP-2 panel's current brightness to the intel_backlight device.
FIRST_SCREEN_BRIGHTNESS=$(echo /sys/class/backlight/*-eDP-2-backlight/brightness)
SECOND_SCREEN_BRIGHTNESS="/sys/class/backlight/intel_backlight/brightness"
BRIGHTNESS=$(cat "$FIRST_SCREEN_BRIGHTNESS")
echo "$BRIGHTNESS" | sudo tee "$SECOND_SCREEN_BRIGHTNESS"
