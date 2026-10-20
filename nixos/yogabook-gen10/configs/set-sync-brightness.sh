#!/usr/bin/env bash
VALUE=${1:-5}
brightnessctl -d '*-eDP-2-backlight' --save
brightnessctl -d 'intel_backlight' --save
brightnessctl -d '*-eDP-2-backlight' s "${VALUE}%"
brightnessctl -d 'intel_backlight' s "${VALUE}%"
