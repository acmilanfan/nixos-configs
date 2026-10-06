#!/bin/bash

# Controller for the tag items (space.1-20, space.S), run once per nanowm_update.
# Sets every item in a single sketchybar call instead of one script process per item.
#
# Inputs from nanowm: TAG (focused tag, or S), ACTIVE_TAGS (the tag shown on each screen),
# OCCUPIED, URGENT, SCREENS (screen count).
#
# Display: nanowm puts tags 1-10 on screen 1 and 11-20 on screen 2, so their items go on that
# display when it exists; otherwise (one screen holds every tag) on display 1. S is on display 1.

[ "$SENDER" = "nanowm_update" ] || exit 0

SCREENS=${SCREENS:-1}

contains() { # contains <word> <list>
  local w
  for w in $2; do [ "$w" = "$1" ] && return 0; done
  return 1
}

args=()
for id in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 S; do
  display=1
  if [ "$id" != "S" ]; then
    monitor=$(( (id - 1) / 10 + 1 ))
    [ "$monitor" -le "$SCREENS" ] && display=$monitor
  fi

  if [ "$TAG" = "$id" ]; then
    # Focused tag - highlighted purple
    style="drawing=on background.drawing=on background.color=0xff7b5cff icon.color=0xff1a1b26"
  elif contains "$id" "$URGENT"; then
    # Urgent - red (attention needed)
    style="drawing=on background.drawing=on background.color=0xfff7768e icon.color=0xff1a1b26"
  elif [ "$id" != "S" ] && contains "$id" "$ACTIVE_TAGS"; then
    # Shown on its screen but not focused (e.g. the other monitor's tag) - lighter, even if empty
    style="drawing=on background.drawing=on background.color=0xff565f89 icon.color=0xffc0caf5"
  elif contains "$id" "$OCCUPIED"; then
    # Has windows but not shown - dimmed
    style="drawing=on background.drawing=on background.color=0xff3b4261 icon.color=0xffc0caf5"
  else
    # Empty - hidden
    style="drawing=off"
  fi

  # shellcheck disable=SC2206 # style is a list of key=value words
  args+=(--set "space.$id" "display=$display" $style)
done

sketchybar "${args[@]}"
