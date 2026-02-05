#!/bin/bash

# Kanata Configuration Switcher
# Usage: ./switch-kanata.sh [default|homerow]

set -e

CONFIG_DIR="$HOME/.config/kanata"
ACTIVE_CONFIG="$CONFIG_DIR/active_config.kbd"
DEFAULT_SOURCE="$CONFIG_DIR/kanata-default.kbd"
HOMEROW_SOURCE="$CONFIG_DIR/kanata-homerow.kbd"
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
    *)
        echo "Usage: $0 [default|homerow]"
        exit 1
        ;;
esac

# Execute reload
if [[ -f "$RELOAD_SCRIPT" ]]; then
    bash "$RELOAD_SCRIPT"
else
    echo "Reload script not found at $RELOAD_SCRIPT"
    exit 1
fi
