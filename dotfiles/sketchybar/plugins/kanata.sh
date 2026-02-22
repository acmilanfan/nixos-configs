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
    esac

    sketchybar --set "$NAME" icon="$icon" icon.color="$color"
}

popup() {
    sketchybar --set "$NAME" popup.drawing=toggle
}

switch_mode() {
    local mode="$1"
    if [ -f "$SWITCH_SCRIPT" ]; then
        # Feedback: Loading state
        sketchybar --set kanata icon="󱑊" icon.color=0xffe0af68 popup.drawing=off

        # Run switch in background so bar doesn't hang, but wait for it
        bash "$SWITCH_SCRIPT" "$mode" > /tmp/sketchybar_kanata_switch.log 2>&1

        # Feedback: Brief success state
        sketchybar --set kanata icon="󰄬" icon.color=0xff9ece6a
        sleep 1

        update
    fi
}

case "$SENDER" in
    "routine" | "forced")
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
esac
