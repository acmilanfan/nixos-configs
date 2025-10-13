#!/bin/bash

# Window highlighting script for AeroSpace using JankyBorders
# This script manages JankyBorders to highlight the currently focused window

# Colors (matching SketchyBar theme)
ACTIVE_COLOR="0xff007acc"      # Blue for focused window
INACTIVE_COLOR="0x00000000"    # Transparent for unfocused windows
BORDER_WIDTH=2.0

# Function to check if accordion mode is active
is_accordion_mode() {
    # Check if accordion mode state file exists and contains "true"
    local accordion_state_file="/tmp/aerospace-accordion-mode"
    if [[ -f "$accordion_state_file" ]]; then
        local state=$(cat "$accordion_state_file" 2>/dev/null)
        if [[ "$state" == "true" ]]; then
            return 0
        fi
    fi
    return 1
}

# Function to check if highlighting should be enabled
should_highlight() {
    # Check if aerospace is available
    if ! command -v aerospace >/dev/null 2>&1; then
        echo "AeroSpace not found, enabling highlighting by default"
        return 0
    fi

    # Check if accordion mode is active - if so, disable highlighting
    if is_accordion_mode; then
        echo "Accordion mode is active, disabling highlighting"
        return 1
    fi

    # Get current focused workspace
    local focused_workspace
    focused_workspace=$(aerospace list-workspaces --focused 2>/dev/null)

    if [[ -z "$focused_workspace" ]]; then
        echo "Could not determine focused workspace, enabling highlighting by default"
        return 0
    fi

    # Count windows in the focused workspace
    local window_count
    window_count=$(aerospace list-windows --workspace "$focused_workspace" --format '%{window-id}' 2>/dev/null | wc -l | xargs)

    if [[ -z "$window_count" ]] || [[ "$window_count" -eq 0 ]]; then
        echo "No windows found or error counting windows, enabling highlighting by default"
        return 0
    fi

    # Only highlight if there are 2 or more windows
    if [[ "$window_count" -gt 1 ]]; then
        echo "Found $window_count windows, enabling highlighting"
        return 0
    else
        echo "Found only $window_count window, disabling highlighting"
        return 1
    fi
}

# Function to start JankyBorders with proper configuration
start_jankyborders() {
    # Kill existing borders process
    killall borders 2>/dev/null

    # Check if highlighting should be enabled
    if ! should_highlight; then
        echo "JankyBorders disabled - only one window in current workspace"
        return 0
    fi

    # Start JankyBorders with configuration
    if command -v borders >/dev/null 2>&1; then
        borders \
            active_color="$ACTIVE_COLOR" \
            inactive_color="$INACTIVE_COLOR" \
            width="$BORDER_WIDTH" \
            hidpi=on \
            style=round \
            blacklist="Finder,System Preferences,Activity Monitor,Calculator,Archive Utility,Maccy" &

        echo "JankyBorders started with window highlighting"
    else
        echo "JankyBorders not found. Please install it with: brew install FelixKratz/formulae/borders"
        return 1
    fi
}

# Function to stop JankyBorders
stop_jankyborders() {
    killall borders 2>/dev/null
    echo "JankyBorders stopped"
}

# Function to restart JankyBorders
restart_jankyborders() {
    stop_jankyborders
    sleep 0.5
    start_jankyborders
}

# Function to check if JankyBorders is running
is_running() {
    pgrep -x borders >/dev/null
}

# Function to install JankyBorders if not available
install_jankyborders() {
    if ! command -v borders >/dev/null 2>&1; then
        echo "Installing JankyBorders..."
        if command -v brew >/dev/null 2>&1; then
            brew tap FelixKratz/formulae
            brew install borders
        else
            echo "Homebrew not found. Please install JankyBorders manually from: https://github.com/FelixKratz/JankyBorders"
            return 1
        fi
    else
        echo "JankyBorders is already installed"
    fi
}

# Function to toggle JankyBorders
toggle_jankyborders() {
    if is_running; then
        stop_jankyborders
    else
        start_jankyborders
    fi
}

# Main execution
case "${1:-start}" in
    "start")
        start_jankyborders
        ;;
    "stop")
        stop_jankyborders
        ;;
    "restart")
        restart_jankyborders
        ;;
    "toggle")
        toggle_jankyborders
        ;;
    "status")
        if is_running; then
            echo "JankyBorders is running"
        else
            echo "JankyBorders is not running"
        fi
        ;;
    "install")
        install_jankyborders
        ;;
    "daemon")
        # Legacy compatibility - just start JankyBorders
        start_jankyborders
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|toggle|status|install}"
        echo "  start    - Start JankyBorders with window highlighting"
        echo "  stop     - Stop JankyBorders"
        echo "  restart  - Restart JankyBorders"
        echo "  toggle   - Toggle JankyBorders on/off"
        echo "  status   - Check if JankyBorders is running"
        echo "  install  - Install JankyBorders via Homebrew"
        exit 1
        ;;
esac

