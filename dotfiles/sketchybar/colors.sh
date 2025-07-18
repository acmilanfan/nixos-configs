#!/bin/bash

# Color Palette based on FelixKratz official SketchyBar configuration
# https://github.com/FelixKratz/dotfiles

# Base Colors (from official config)
export BLACK=0xff181819
export WHITE=0xffe2e2e3
export RED=0xfffc5d7c
export GREEN=0xff9ed072
export BLUE=0xff76cce0
export YELLOW=0xffe7c664
export ORANGE=0xfff39660
export MAGENTA=0xffb39df3
export GREY=0xff7f8490
export TRANSPARENT=0x00000000

# Bar Colors (from official config)
export BAR_COLOR=0xf02c2e34          # Semi-transparent dark background
export BAR_BORDER_COLOR=0xff2c2e34   # Solid dark border

# Item Colors (from official config)
export ICON_COLOR=$WHITE             # White icons
export LABEL_COLOR=$WHITE            # White labels
export BACKGROUND_1=0xff363944       # Background layer 1
export BACKGROUND_2=0xff414550       # Background layer 2

# Popup Colors (from official config)
export POPUP_BACKGROUND_COLOR=0xc02c2e34
export POPUP_BORDER_COLOR=$GREY

# Workspace Colors
export SPACE_ACTIVE=0x40ffffff       # Semi-transparent white for active
export SPACE_INACTIVE=$GREY          # Grey for inactive

# Widget specific colors (using official palette)
export CPU_COLOR=$GREEN              # Green for CPU
export MEMORY_COLOR=$ORANGE          # Orange for memory
export BATTERY_COLOR=$BLUE           # Blue for battery
export VOLUME_COLOR=$MAGENTA         # Magenta for volume

# General accent color
export ACCENT_COLOR=$BLUE            # Blue accent

