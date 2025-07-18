#!/bin/bash

# Script to restart SketchyBar with proper configuration
# This script helps test and restart SketchyBar after configuration changes

echo "=== SketchyBar Restart Script ==="
echo

# Set configuration directory
export CONFIG_DIR="$HOME/.config/sketchybar"

# Check if SketchyBar is installed
if ! command -v sketchybar >/dev/null 2>&1; then
    echo "❌ SketchyBar not found. Please install it first."
    exit 1
else
    echo "✅ SketchyBar found"
fi

# Check if AeroSpace is available (required for workspace functionality)
if ! command -v aerospace >/dev/null 2>&1; then
    echo "⚠️  AeroSpace not found. Workspace functionality may not work properly."
else
    echo "✅ AeroSpace found"
fi

echo

# Kill existing SketchyBar processes
echo "Stopping existing SketchyBar processes..."
killall sketchybar 2>/dev/null
sleep 1

# Check if configuration directory exists
if [[ ! -d "$CONFIG_DIR" ]]; then
    echo "❌ Configuration directory not found: $CONFIG_DIR"
    echo "Please make sure your SketchyBar configuration is properly linked."
    exit 1
else
    echo "✅ Configuration directory found: $CONFIG_DIR"
fi

# Check if main configuration file exists
if [[ ! -f "$CONFIG_DIR/sketchybarrc" ]]; then
    echo "❌ Main configuration file not found: $CONFIG_DIR/sketchybarrc"
    exit 1
else
    echo "✅ Main configuration file found"
fi

# Test configuration syntax
echo "Testing configuration syntax..."
if bash -n "$CONFIG_DIR/sketchybarrc"; then
    echo "✅ Configuration syntax is valid"
else
    echo "❌ Configuration syntax error found"
    exit 1
fi

echo

# Start SketchyBar
echo "Starting SketchyBar..."
sketchybar --config "$CONFIG_DIR/sketchybarrc" &

# Wait a moment for startup
sleep 2

# Check if SketchyBar is running
if pgrep -x sketchybar >/dev/null; then
    echo "✅ SketchyBar started successfully"
    
    # Show current workspace info if AeroSpace is available
    if command -v aerospace >/dev/null 2>&1; then
        echo
        echo "Current workspace information:"
        focused_workspace=$(aerospace list-workspaces --focused 2>/dev/null)
        if [[ -n "$focused_workspace" ]]; then
            echo "  Focused workspace: $focused_workspace"
            window_count=$(aerospace list-windows --workspace "$focused_workspace" --format '%{window-id}' 2>/dev/null | wc -l | xargs)
            echo "  Window count: $window_count"
        fi
    fi
else
    echo "❌ SketchyBar failed to start"
    echo "Check the logs for more information:"
    echo "  tail -f /tmp/sketchybar_*.log"
    exit 1
fi

echo
echo "SketchyBar restart completed successfully!"
echo
echo "If you encounter issues:"
echo "1. Check SketchyBar logs: tail -f /tmp/sketchybar_*.log"
echo "2. Verify AeroSpace is running: aerospace list-workspaces"
echo "3. Test individual plugins manually"
