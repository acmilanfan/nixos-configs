#!/bin/bash

# Kanata Configuration Switcher
# Usage: ./switch-kanata.sh [default|homerow|split|angle]

set -e

# Ensure standard paths are available
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

CONFIG_DIR="$HOME/.config/kanata"
ACTIVE_CONFIG="$CONFIG_DIR/active_config.kbd"
DEFAULT_SOURCE="$CONFIG_DIR/kanata-default.kbd"
HOMEROW_SOURCE="$CONFIG_DIR/kanata-homerow.kbd"
SPLIT_SOURCE="$CONFIG_DIR/kanata-split.kbd"
ANGLE_SOURCE="$CONFIG_DIR/kanata-angle.kbd"
DISABLED_SOURCE="$CONFIG_DIR/kanata-disabled.kbd"
RELOAD_SCRIPT="$CONFIG_DIR/reload-kanata.sh"

MODE=$1

case $MODE in
    default)
        echo "Switching to Standard configuration..."
        ln -sf "$DEFAULT_SOURCE" "$ACTIVE_CONFIG"
        ;;
    homerow)
        echo "Switching to Home Row Mods configuration..."
        ln -sf "$HOMEROW_SOURCE" "$ACTIVE_CONFIG"
        ;;
    split)
        echo "Switching to Split layout configuration..."
        ln -sf "$SPLIT_SOURCE" "$ACTIVE_CONFIG"
        ;;
    angle)
        echo "Switching to Angle Mod configuration..."
        ln -sf "$ANGLE_SOURCE" "$ACTIVE_CONFIG"
        ;;
    disabled)
        echo "Switching to Disabled configuration..."
        ln -sf "$DISABLED_SOURCE" "$ACTIVE_CONFIG"
        ;;
    *)
        echo "Usage: $0 [default|homerow|split|angle|disabled]"
        exit 1
        ;;
esac

# Execute reload
if [[ -f "$RELOAD_SCRIPT" ]]; then
    echo "Executing reload script: $RELOAD_SCRIPT"
    bash "$RELOAD_SCRIPT"

    # Notify SketchyBar of the change
    if command -v sketchybar >/dev/null 2>&1; then
        sketchybar --trigger kanata_changed
    fi
else
    echo "Reload script not found at $RELOAD_SCRIPT"
    exit 1
fi
