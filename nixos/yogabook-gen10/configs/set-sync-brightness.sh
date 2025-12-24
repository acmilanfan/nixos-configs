#!/usr/bin/env bash

VALUE=${1:-5}

brightnessctl --device='card0-eDP-2-backlight' --save
brightnessctl --device='intel_backlight' --save
brightnessctl --device='card0-eDP-2-backlight' s ${VALUE}%
brightnessctl --device='intel_backlight' s ${VALUE}%
