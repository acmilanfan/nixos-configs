#!/bin/bash

# Space windows plugin - shows/hides spaces based on window presence
# Only displays workspaces that have windows opened

source "$CONFIG_DIR/colors.sh"

# Get all workspaces with windows
WORKSPACES_WITH_WINDOWS=$(aerospace list-workspaces --monitor all | while read -r workspace; do
    window_count=$(aerospace list-windows --workspace "$workspace" --format '%{window-id}' | wc -l | xargs)
    if [[ "$window_count" -gt 0 ]]; then
        echo "$workspace"
    fi
done)

# Get current focused workspace
FOCUSED_WORKSPACE=$(aerospace list-workspaces --focused)

# Always show focused workspace even if empty
if [[ -n "$FOCUSED_WORKSPACE" ]]; then
    WORKSPACES_WITH_WINDOWS=$(echo -e "$WORKSPACES_WITH_WINDOWS\n$FOCUSED_WORKSPACE" | sort -n | uniq)
fi

# Hide all spaces first (only show first 10 spaces like official config)
for sid in {1..10}; do
    sketchybar --set space.$sid drawing=off
done

# Show only spaces with windows or focused space
for workspace in $WORKSPACES_WITH_WINDOWS; do
    if [[ "$workspace" =~ ^[0-9]+$ ]] && [[ "$workspace" -ge 1 ]] && [[ "$workspace" -le 10 ]]; then
        sketchybar --set space.$workspace drawing=on
        
        if [[ "$workspace" == "$FOCUSED_WORKSPACE" ]]; then
            # Focused workspace
            sketchybar --set space.$workspace background.drawing=on \
                                            background.color=$WHITE \
                                            icon.color=$BLACK
        else
            # Non-focused workspace with windows
            sketchybar --set space.$workspace background.drawing=off \
                                            icon.color=$WHITE
        fi
    fi
done

