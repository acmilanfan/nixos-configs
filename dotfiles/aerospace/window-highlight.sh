#!/bin/bash

# Window highlighting script for AeroSpace using JankyBorders
# This script manages JankyBorders to highlight the currently focused window

# Colors (matching SketchyBar theme)
ACTIVE_COLOR="0xff007acc"      # Blue for focused window
INACTIVE_COLOR="0x00000000"    # Transparent for unfocused windows
BORDER_WIDTH=3.0

# Function to start JankyBorders with proper configuration
start_jankyborders() {
    # Kill existing borders process
    killall borders 2>/dev/null
    
    # Start JankyBorders with configuration
    if command -v borders >/dev/null 2>&1; then
        borders \
            active_color="$ACTIVE_COLOR" \
            inactive_color="$INACTIVE_COLOR" \
            width="$BORDER_WIDTH" \
            hidpi=on \
            style=round \
            radius=9.0 \
            animation_duration=0.15 \
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

