#!/bin/bash

# Kanata Configuration Widget for SketchyBar
# Shows current mode and allows switching via popup

ACTIVE_CONFIG="$HOME/.config/kanata/active_config.kbd"
SWITCH_SCRIPT="$HOME/.config/kanata/switch-kanata.sh"

update() {
    local target
    if [ -L "$ACTIVE_CONFIG" ]; then
        target=$(readlink "$ACTIVE_CONFIG")
    else
        target="unknown"
    fi

    local icon="󰌌"
    local label="Unknown"
    local color=0xffc0caf5 # WHITE

    case "$target" in
        *kanata-default.kbd)
            label="Standard"
            icon="󰌌"
            color=0xff9ece6a # Green
            ;;
        *kanata-homerow.kbd | *kanata.kbd)
            label="Homerow"
            icon="󰓁"
            color=0xff7b5cff # Purple
            ;;
        *kanata-split.kbd | *kanata-split-fixed.kbd)
            label="Split"
            icon="󰗵"
            color=0xffe0af68 # Yellow
            ;;
        *kanata-angle.kbd)
            label="Angle"
            icon="󰓁"
            color=0xff7dcfff # Cyan
            ;;
    esac

    # Always update the main 'kanata' item, regardless of which popup item triggered the script
    sketchybar --set kanata icon="$icon" icon.color="$color"
}

popup() {
    sketchybar --set kanata popup.drawing=toggle
}

switch_mode() {
    local mode="$1"
    if [ -f "$SWITCH_SCRIPT" ]; then
        # Feedback: Loading state
        sketchybar --set kanata icon="󱑊" icon.color=0xffe0af68 popup.drawing=off

        # Run switch (this script will trigger 'kanata_changed' event)
        bash "$SWITCH_SCRIPT" "$mode" > /tmp/sketchybar_kanata_switch.log 2>&1

        # No need to call update or sleep here;
        # the 'kanata_changed' event triggered by switch-kanata.sh will handle it.
    fi
}

case "$SENDER" in
    "routine" | "forced" | "kanata_changed")
        update
        ;;
    "mouse.clicked")
        if [ "$BUTTON" = "left" ]; then
            popup
        fi
        ;;
    "kanata_switch_default")
        switch_mode "default"
        ;;
    "kanata_switch_homerow")
        switch_mode "homerow"
        ;;
    "kanata_switch_split")
        switch_mode "split"
        ;;
    "kanata_switch_angle")
        switch_mode "angle"
        ;;
esac
