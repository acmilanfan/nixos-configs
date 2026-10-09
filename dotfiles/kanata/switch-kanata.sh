#!/bin/bash

# Kanata Configuration Switcher
# Usage: ./switch-kanata.sh [default|homerow|split|angle|disabled|training]

set -e

# Ensure standard paths are available
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

CONFIG_DIR="$HOME/.config/kanata"
ACTIVE_CONFIG="$CONFIG_DIR/active_config.kbd"
RELOAD_SCRIPT="$CONFIG_DIR/reload-kanata.sh"

MODE=$1

# Home Manager installs each mode under its plain name and, on ISO Macs
# (mac-home), already points those names at the *-iso.kbd variants. So always
# link the plain name: kanata-<mode>-iso.kbd is never installed, and linking it
# left kanata crash-looping on a missing config.
case $MODE in
    default|homerow|split|angle|disabled|training)
        echo "Switching to $MODE configuration..."
        ln -sf "$CONFIG_DIR/kanata-$MODE.kbd" "$ACTIVE_CONFIG"
        ;;
    *)
        echo "Usage: $0 [default|homerow|split|angle|disabled|training]"
        exit 1
        ;;
esac

# kanata re-reads its --cfg path (the symlink above) on a TCP Reload, so a
# mode switch needs neither a restart nor root. Fall back to the full reload
# script if the TCP server doesn't answer (kanata down or wedged).
if printf '{"Reload":{}}\n' | nc -w 2 127.0.0.1 5829 >/dev/null 2>&1; then
    echo "Reloaded kanata over TCP."
    if command -v sketchybar >/dev/null 2>&1; then
        sketchybar --trigger kanata_changed
    fi
    exit 0
fi
echo "kanata TCP server not answering; doing a full reload."

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
