#!/bin/bash

# Smart Kanata Health Check & Reload Script
# Only reloads if something is actually broken or environment changed

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

# 1. Check if Main instance is running
if ! pgrep -f "^/opt/homebrew/bin/kanata.*--port 5829" >/dev/null; then
    RELOAD_REQUIRED=true
    REASON="Main Kanata instance is not running"
fi

# 2. Check if Karabiner Grabber is running (it shouldn't be, it steals HID access)
if pgrep -x "karabiner_grabber" >/dev/null; then
    RELOAD_REQUIRED=true
    REASON="Karabiner Grabber is active and might have stolen HID access"
fi

# 3. Check for external keyboards (Charybdis/Aurora)
# If they are connected but Charybdis instance is NOT running, reload.
EXTERNAL_CONNECTED=false
if ioreg -rn "Charybdis" >/dev/null 2>&1 || ioreg -rn "Aurora Sweep" >/dev/null 2>&1 || ioreg -rn "Splinky" >/dev/null 2>&1; then
    EXTERNAL_CONNECTED=true
fi

if [ "$EXTERNAL_CONNECTED" = true ]; then
    if ! pgrep -f "^/opt/homebrew/bin/kanata.*--port 5830" >/dev/null; then
        RELOAD_REQUIRED=true
        REASON="External keyboard detected but Charybdis instance is not running"
    fi
fi

# 4. Check if Internal Keyboard is actually grabbed
# We look for Kanata's virtual HID device or the lack of native HID reports if possible.
# A simpler way: check if the 'kanata' process has open files related to the keyboard.
if [ "$RELOAD_REQUIRED" = false ]; then
    # If we find any 'Error' in the last 10 lines of the log, reload.
    if tail -n 10 /tmp/kanata.error.log 2>/dev/null | grep -qi "error"; then
        RELOAD_REQUIRED=true
        REASON="Errors detected in Kanata logs"
    fi
fi

# Force reload if --force is passed
if [[ "$*" == *"--force"* ]]; then
    RELOAD_REQUIRED=true
    REASON="Manual force reload requested"
fi

if [ "$RELOAD_REQUIRED" = true ]; then
    print_warning "Reloading Kanata: $REASON"
    
    # Aggressive kill
    sudo pkill -9 "karabiner_grabber" 2>/dev/null || true
    sudo pkill -9 -f "kanata" 2>/dev/null || true
    
    # Notify launchd will handle restart via KeepAlive=true
    print_status "✓ Rapid restart triggered."
else
    print_status "✓ Kanata is healthy. Skipping reload."
fi
