#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════
# SKETCHYBAR DEFAULTS
# ═══════════════════════════════════════════════════════════════════════════

FONT_FACE="JetBrainsMono Nerd Font"
export ICON_FONT="$FONT_FACE:Regular:14.0"
export LABEL_FONT="$FONT_FACE:Medium:11.0"
export LABEL_FONT_BOLD="$FONT_FACE:Bold:11.0"

sketchybar --default \
  updates=on \
  drawing=on \
  icon.font="$ICON_FONT" \
  label.font="$LABEL_FONT" \
  icon.color=$WHITE \
  label.color=$WHITE \
  background.height=22 \
  background.corner_radius=6 \
  label.padding_left=4 \
  label.padding_right=6 \
  icon.padding_left=6 \
  icon.padding_right=4 \
  background.padding_right=2 \
  background.padding_left=2

sketchybar --bar \
  height=32 \
  color=$BAR_COLOR \
  position=top \
  sticky=on \
  topmost=window \
  padding_left=6 \
  padding_right=20 \
  shadow=on
