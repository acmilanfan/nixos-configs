#!/bin/bash

CONFIG_DIR="$HOME/.config/kanata"
ACTIVE_CONFIG="$CONFIG_DIR/active_config.kbd"

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

type=$1

case $type in
    homerow)
        echo "Switching to Home Row Mods configuration..."
        ln -sf "$CONFIG_DIR/kanata-yogabook.kbd" "$ACTIVE_CONFIG"
        ;;
    disabled)
        echo "Switching to Disabled configuration..."
        ln -sf "$CONFIG_DIR/kanata-disabled.kbd" "$ACTIVE_CONFIG"
        ;;
    *)
        echo "Usage: $0 [homerow|disabled]"
        echo ""
        echo "  homerow  - Home row mods with mouse keys layer"
        echo "  disabled - Block all kanata processing (pass-through)"
        exit 1
        ;;
esac

echo "Restarting kanata..."
systemctl --user restart kanata 2>/dev/null || \
    systemctl restart kanata 2>/dev/null || \
    echo "Warning: Could not restart kanata via systemd. Run: systemctl --user restart kanata"

echo "Kanata switched to: $type"
