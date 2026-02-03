#!/bin/bash

# Extract space number from item name (space.1 -> 1, space.S -> S)
SPACE_ID=$(echo "$NAME" | cut -d. -f2)

if [ "$SENDER" = "nanowm_update" ]; then
  IS_ACTIVE=false
  HAS_WINDOWS=false
  IS_URGENT=false

  # Check if this space is the current tag
  if [ "$TAG" = "$SPACE_ID" ]; then
    IS_ACTIVE=true
  fi

  # Check if this space has windows (is in OCCUPIED list)
  for occupied in $OCCUPIED; do
    if [ "$occupied" = "$SPACE_ID" ]; then
      HAS_WINDOWS=true
      break
    fi
  done

  # Check if this space is urgent
  for urgent in $URGENT; do
    if [ "$urgent" = "$SPACE_ID" ]; then
      IS_URGENT=true
      break
    fi
  done

  if [ "$IS_ACTIVE" = true ]; then
    # Current workspace - highlighted blue
    sketchybar --set "$NAME" drawing=on background.drawing=on background.color=0xff7b5cff icon.color=0xff1a1b26
  elif [ "$IS_URGENT" = true ]; then
    # Urgent workspace - highlighted red/orange (attention needed!)
    sketchybar --set "$NAME" drawing=on background.drawing=on background.color=0xfff7768e icon.color=0xff1a1b26
  elif [ "$HAS_WINDOWS" = true ]; then
    # Has windows but not active - visible but dimmed
    sketchybar --set "$NAME" drawing=on background.drawing=on background.color=0xff3b4261 icon.color=0xffc0caf5
  else
    # Empty workspace - hidden
    sketchybar --set "$NAME" drawing=off
  fi
fi
