#!/usr/bin/env bash
brightnessctl --device='card1-eDP-2-backlight' -r
brightnessctl --device='intel_backlight' -r
brightness-ctl restore
