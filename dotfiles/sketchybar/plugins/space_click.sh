#!/bin/bash

# Extract space number from item name (space.1 -> 1, space.S -> S)
SPACE_ID=$(echo "$NAME" | cut -d. -f2)

# Use hs CLI to switch to the workspace
if [ "$SPACE_ID" = "S" ]; then
  /opt/homebrew/bin/hs -c "NanoWM.toggleSpecial()"
else
  /opt/homebrew/bin/hs -c "NanoWM.gotoTag($SPACE_ID)"
fi
