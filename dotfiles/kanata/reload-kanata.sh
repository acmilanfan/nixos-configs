#!/bin/bash

# Smart Kanata Health Check & Reload Script
# Only reloads if something is actually broken or environment changed
# Unless --force is passed, which performs a full ordered reset.

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

RELOAD_REQUIRED=false
REASON=""
FORCE=false

if [[ "$*" == *"--force"* ]]; then
    FORCE=true
    RELOAD_REQUIRED=true
    REASON="Manual force reload requested"
fi

# 1. Check if Main instance is running
if [ "$RELOAD_REQUIRED" = false ]; then
    if ! pgrep -f "^/usr/local/bin/kanata-nix.*--port 5829" >/dev/null; then
        RELOAD_REQUIRED=true
        REASON="Main Kanata instance is not running"
    fi
fi

# 2. Check if Karabiner Grabber is running (it shouldn't be, it steals HID access)
if [ "$RELOAD_REQUIRED" = false ]; then
    if pgrep -x "karabiner_grabber" >/dev/null; then
        RELOAD_REQUIRED=true
        REASON="Karabiner Grabber is active and might have stolen HID access"
    fi
fi

# 3. Check for external keyboards
# We check if an external keyboard is connected but no secondary kanata is running.
EXTERNAL_CONNECTED=false
if ioreg -rn "Charybdis" >/dev/null 2>&1 || ioreg -rn "Aurora" >/dev/null 2>&1 || ioreg -rn "Splinky" >/dev/null 2>&1 || ioreg -c IOHIDDevice | grep -qi "Keyboard"; then
    # Filter out the Apple Internal Keyboard from the 'Keyboard' grep
    if ioreg -c IOHIDDevice | grep -i "Product" | grep -v "Apple Internal" | grep -qi "Keyboard"; then
        EXTERNAL_CONNECTED=true
    fi
fi

if [ "$RELOAD_REQUIRED" = false ] && [ "$EXTERNAL_CONNECTED" = true ]; then
    if ! pgrep -f "^/usr/local/bin/kanata-nix.*--port 5830" >/dev/null; then
        RELOAD_REQUIRED=true
        REASON="External keyboard detected but Charybdis instance is not running"
    fi
fi

if [ "$RELOAD_REQUIRED" = true ]; then
    print_warning "Reloading Kanata: $REASON"
    
    # 1. Aggressive kill of any interfering processes
    sudo pkill -9 "karabiner_grabber" 2>/dev/null || true
    sudo pkill -9 -f "kanata" 2>/dev/null || true
    sleep 0.2

    # 2. Restart Main Instance
    print_status "Restarting Main Kanata (Port 5829)..."
    sudo launchctl kickstart -k system/local.kanata
    
    # 3. If forcing, we wait to ensure Main gets the HID grab before Charybdis
    if [ "$FORCE" = true ]; then
        for i in {1..20}; do
            if pgrep -f "^/usr/local/bin/kanata-nix.*--port 5829" >/dev/null; then
                print_status "✓ Main instance ready."
                break
            fi
            sleep 0.2
        done
    fi

    # 4. Restart Charybdis Instance
    if [[ -f "/Library/LaunchDaemons/local.kanata-charibdis.plist" ]]; then
        print_status "Restarting Charybdis Kanata (Port 5830)..."
        sudo launchctl kickstart -k system/local.kanata-charibdis
    fi

    # 5. Restart Agents
    launchctl kickstart -k "gui/$(id -u)/local.kanata-vk-agent" 2>/dev/null || true
    if [[ -f "/Library/LaunchAgents/local.kanata-vk-agent-charibdis.plist" ]]; then
        launchctl kickstart -k "gui/$(id -u)/local.kanata-vk-agent-charibdis" 2>/dev/null || true
    fi
    
    print_status "✓ Reload complete."
else
    print_status "✓ Kanata is healthy. Skipping reload."
fi
