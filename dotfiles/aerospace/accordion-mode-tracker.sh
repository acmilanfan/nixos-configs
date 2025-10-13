#!/bin/bash

# Accordion mode tracker for AeroSpace
# This script tracks the current layout mode and updates the state file

ACCORDION_STATE_FILE="/tmp/aerospace-accordion-mode"

# Function to set accordion mode state
set_accordion_mode() {
    local mode="$1"
    echo "$mode" > "$ACCORDION_STATE_FILE"
    
    # Trigger window highlight daemon update
    if command -v aerospace-highlight-daemon >/dev/null 2>&1; then
        aerospace-highlight-daemon update 2>/dev/null || true
    elif [[ -f "/Users/andreishumailov/.config/aerospace/window-highlight-daemon.sh" ]]; then
        "/Users/andreishumailov/.config/aerospace/window-highlight-daemon.sh" update 2>/dev/null || true
    fi
}

# Function to get current accordion mode state
get_accordion_mode() {
    if [[ -f "$ACCORDION_STATE_FILE" ]]; then
        cat "$ACCORDION_STATE_FILE" 2>/dev/null || echo "false"
    else
        echo "false"
    fi
}

# Function to toggle accordion mode
toggle_accordion_mode() {
    local current_mode
    current_mode=$(get_accordion_mode)
    
    if [[ "$current_mode" == "true" ]]; then
        # Switch to tiles mode
        aerospace layout tiles
        set_accordion_mode "false"
        echo "Switched to tiles mode"
    else
        # Switch to accordion mode
        aerospace layout accordion
        set_accordion_mode "true"
        echo "Switched to accordion mode"
    fi
}

# Main execution
case "${1:-status}" in
    "enable"|"on"|"true")
        set_accordion_mode "true"
        echo "Accordion mode enabled"
        ;;
    "disable"|"off"|"false")
        set_accordion_mode "false"
        echo "Accordion mode disabled"
        ;;
    "toggle")
        toggle_accordion_mode
        ;;
    "status"|"get")
        current_mode=$(get_accordion_mode)
        echo "Accordion mode: $current_mode"
        ;;
    *)
        echo "Usage: $0 {enable|disable|toggle|status}"
        echo "  enable   - Enable accordion mode tracking"
        echo "  disable  - Disable accordion mode tracking"
        echo "  toggle   - Toggle between tiles and accordion mode"
        echo "  status   - Show current accordion mode status"
        exit 1
        ;;
esac
