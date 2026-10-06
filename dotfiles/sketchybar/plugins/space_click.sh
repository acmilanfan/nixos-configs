#!/bin/bash

# Extract space number from item name (space.1 -> 1, space.S -> S)
SPACE_ID=$(echo "$NAME" | cut -d. -f2)

# Switch via nanowm's URL handler (nanowm/init.lua) rather than `hs -c`, whose IPC port can wedge
if [ "$SPACE_ID" = "S" ]; then
  /usr/bin/open -g "hammerspoon://nanowm?cmd=toggleSpecial"
else
  /usr/bin/open -g "hammerspoon://nanowm?cmd=gotoTag&tag=$SPACE_ID"
fi
