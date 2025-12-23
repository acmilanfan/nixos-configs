#!/usr/bin/env bash

VALUE=${1:-5}

brightnessctl s ${VALUE}%
brightnessctl --device='intel_backlight' s ${VALUE}%
