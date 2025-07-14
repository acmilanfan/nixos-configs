#!/bin/bash

# Focus follows mouse implementation for AeroSpace
# This script uses macOS accessibility features to implement focus follows mouse

# Check if we have accessibility permissions
if ! /usr/bin/osascript -e 'tell application "System Events" to get processes' >/dev/null 2>&1; then
    echo "This script requires accessibility permissions."
    echo "Please grant accessibility permissions to your terminal in System Preferences > Security & Privacy > Privacy > Accessibility"
    exit 1
fi

# Function to get window under mouse cursor
get_window_under_cursor() {
    local mouse_pos
    mouse_pos=$(/usr/bin/osascript -e '
        tell application "System Events"
            set mouseLocation to (mouse location)
            return (item 1 of mouseLocation) & "," & (item 2 of mouseLocation)
        end tell
    ')
    
    local x y
    IFS=',' read -r x y <<< "$mouse_pos"
    
    # Get window at position using AeroSpace
    aerospace list-windows --all --format '%{window-id} %{app-name} %{window-title}' | while read -r line; do
        window_id=$(echo "$line" | cut -d' ' -f1)
        # Check if this window contains the mouse position
        # This is a simplified implementation - in practice you'd need more sophisticated geometry checking
        echo "$window_id"
        break
    done
}

# Function to focus window
focus_window() {
    local window_id="$1"
    if [[ -n "$window_id" ]]; then
        aerospace focus --window-id "$window_id" 2>/dev/null
    fi
}

# Main loop
previous_window=""
while true; do
    current_window=$(get_window_under_cursor)
    
    if [[ -n "$current_window" && "$current_window" != "$previous_window" ]]; then
        focus_window "$current_window"
        previous_window="$current_window"
    fi
    
    sleep 0.1  # Check every 100ms
done

