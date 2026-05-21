#!/bin/bash

# Kanata Configuration Switcher
# Usage: ./switch-kanata.sh [default|homerow|split|angle|disabled]

set -e

# Ensure standard paths are available
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

CONFIG_DIR="$HOME/.config/kanata"
ACTIVE_CONFIG="$CONFIG_DIR/active_config.kbd"
RELOAD_SCRIPT="$CONFIG_DIR/reload-kanata.sh"

# Detect Layout based on hostname
HOSTNAME=$(hostname)
LAYOUT="ansi"
if [[ "$HOSTNAME" == *"mac-home"* ]]; then
    LAYOUT="iso"
fi

echo "Detected Layout: $LAYOUT (Machine: $HOSTNAME)"

MODE=$1

case $MODE in
    default)
        echo "Switching to Standard ($LAYOUT) configuration..."
        if [ "$LAYOUT" == "iso" ]; then
            ln -sf "$CONFIG_DIR/kanata-default-iso.kbd" "$ACTIVE_CONFIG"
        else
            ln -sf "$CONFIG_DIR/kanata-default.kbd" "$ACTIVE_CONFIG"
        fi
        ;;
    homerow)
        echo "Switching to Home Row Mods ($LAYOUT) configuration..."
        if [ "$LAYOUT" == "iso" ]; then
            ln -sf "$CONFIG_DIR/kanata-homerow.kbd" "$ACTIVE_CONFIG"
        else
            ln -sf "$CONFIG_DIR/kanata.kbd" "$ACTIVE_CONFIG"
        fi
        ;;
    split)
        echo "Switching to Split layout configuration..."
        ln -sf "$CONFIG_DIR/kanata-split.kbd" "$ACTIVE_CONFIG"
        ;;
    angle)
        echo "Switching to Angle Mod ($LAYOUT) configuration..."
        if [ "$LAYOUT" == "iso" ]; then
            ln -sf "$CONFIG_DIR/kanata-angle-iso.kbd" "$ACTIVE_CONFIG"
        else
            ln -sf "$CONFIG_DIR/kanata-angle.kbd" "$ACTIVE_CONFIG"
        fi
        ;;
    disabled)
        echo "Switching to Disabled configuration..."
        ln -sf "$CONFIG_DIR/kanata-disabled.kbd" "$ACTIVE_CONFIG"
        ;;
    *)
        echo "Usage: $0 [default|homerow|split|angle|disabled]"
        exit 1
        ;;
esac

# Execute reload - ALWAYS use --force when switching modes
if [[ -f "$RELOAD_SCRIPT" ]]; then
    echo "Executing reload script: $RELOAD_SCRIPT --force"
    bash "$RELOAD_SCRIPT" --force

    # Notify SketchyBar of the change
    if command -v sketchybar >/dev/null 2>&1; then
        sketchybar --trigger kanata_changed
    fi
else
    echo "Reload script not found at $RELOAD_SCRIPT"
    exit 1
fi
