#!/bin/bash

# Called when a popup slot is clicked.
# Reads the pane ID, then delegates to Hammerspoon for tag-aware focusing.

SLOT=$(echo "$NAME" | grep -o '[0-9]*$')
PANE_FILE="/tmp/sketchybar_ai_agent_${SLOT}.pane"
[ -f "$PANE_FILE" ] || exit 0
PANE_ID=$(cat "$PANE_FILE" 2>/dev/null)
[ -z "$PANE_ID" ] && exit 0

sketchybar --set ai_agents popup.drawing=off

# Delegate to Hammerspoon for NanoWM tag-aware focus
hs -c "require('nanowm.agents').focusAgent('$PANE_ID')" 2>/dev/null
