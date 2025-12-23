#!/usr/bin/env bash

STEP=${1:-5}

brightnessctl s +${STEP}%
brightnessctl --device='intel_backlight' s +${STEP}%
