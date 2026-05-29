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

# 2. Check if Karabiner Core is running (it shouldn't be, it steals HID access)
# NOTE: We do NOT check for VirtualHIDDevice-Daemon as it is required for Kanata.
if [ "$RELOAD_REQUIRED" = false ]; then
    if pgrep -x "Karabiner-Core-Service" >/dev/null || pgrep -x "karabiner_grabber" >/dev/null; then
        RELOAD_REQUIRED=true
        REASON="Karabiner grabber/service is active and might have stolen HID access"
    fi
fi

if [ "$RELOAD_REQUIRED" = true ]; then
    print_warning "Reloading Kanata: $REASON"

    # 1. Immediate restart - kickstart -k handles killing and starting
    # This is the fastest way to get the keyboard back.
    sudo /bin/launchctl kickstart -k system/local.kanata

    # 2. Parallel background cleanup of interfering processes
    # We redirect everything to /dev/null so parent doesn't wait for pipes
    (
        sudo /bin/launchctl bootout system/org.pqrs.service.daemon.Karabiner-Core-Service 2>/dev/null || true
        sudo /bin/launchctl bootout system/org.pqrs.service.daemon.karabiner_grabber 2>/dev/null || true
        sudo /usr/bin/pkill -x "Karabiner-Core-Service" 2>/dev/null || true
        sudo /usr/bin/pkill -x "karabiner_grabber" 2>/dev/null || true
    ) >/dev/null 2>&1 &

    print_status "✓ Reload initiated (fast path)."
else
    print_status "✓ Kanata is healthy. Skipping reload."
fi
