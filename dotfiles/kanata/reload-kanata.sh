#!/bin/bash

# Unified Kanata Reload Script
# Reloads both Main and Charybdis instances

# Ensure standard paths are available
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

USER_ID=$(id -u)

# Function to clean up a service from all possible domains
cleanup_service() {
    local LABEL=$1
    print_status "Cleaning up $LABEL from all domains..."

    # Try to bootout from GUI domain
    launchctl bootout gui/"$USER_ID"/"$LABEL" 2>/dev/null || true

    # Try to bootout from System domain
    sudo launchctl bootout system/"$LABEL" 2>/dev/null || true

    # Legacy unloads
    launchctl unload "/Library/LaunchAgents/${LABEL}.plist" 2>/dev/null || true
    sudo launchctl unload "/Library/LaunchAgents/${LABEL}.plist" 2>/dev/null || true
    sudo launchctl unload "/Library/LaunchDaemons/${LABEL}.plist" 2>/dev/null || true
}

reload_instance() {
    local KANATA_LABEL=$1
    local AGENT_LABEL=$2
    local PORT=$3

    print_status "--- Reloading $KANATA_LABEL (System) and $AGENT_LABEL (User) (Port $PORT) ---"

    # Aggressively clean up both labels from EVERYWHERE
    cleanup_service "$KANATA_LABEL"
    cleanup_service "$AGENT_LABEL"

    # Global termination check for rogue processes matching this port
    print_status "Ensuring no lingering processes for port $PORT..."
    sudo pkill -9 -f "kanata.*--port $PORT" 2>/dev/null || true
    pkill -9 -f "kanata-vk-agent.*-p $PORT" 2>/dev/null || true

    sleep 2

    local KANATA_PLIST="/Library/LaunchDaemons/${KANATA_LABEL}.plist"
    if [[ -f "$KANATA_PLIST" ]]; then
        print_status "Starting $KANATA_LABEL in System domain..."
        sudo launchctl bootstrap system "$KANATA_PLIST"
    else
        print_warning "Kanata Daemon plist not found at $KANATA_PLIST"
    fi

    local AGENT_PLIST="/Library/LaunchAgents/${AGENT_LABEL}.plist"
    if [[ -f "$AGENT_PLIST" ]]; then
        print_status "Starting $AGENT_LABEL in GUI domain..."
        launchctl bootstrap gui/"$USER_ID" "$AGENT_PLIST"
    else
        print_warning "VK Agent Agent plist not found at $AGENT_PLIST"
    fi

    # 3. Verify
    sleep 3
    local SUCCESS=true
    if ! pgrep -f "kanata.*--port $PORT" >/dev/null; then
        print_error "✗ Kanata ($PORT) failed to start"
        SUCCESS=false
    else
        print_status "✓ Kanata ($PORT) is running"
    fi

    if ! pgrep -f "kanata-vk-agent.*-p $PORT" >/dev/null; then
        print_error "✗ $AGENT_LABEL failed to start"
        SUCCESS=false
    else
        print_status "✓ $AGENT_LABEL is running"
    fi

    return $([ "$SUCCESS" = true ] && echo 0 || echo 1)
}

print_status "Starting Kanata system-wide reload..."

# Stop everything related to Kanata first to be absolutely sure
print_status "Global cleanup of any rogue Kanata processes..."
sudo killall kanata 2>/dev/null || true
killall kanata-vk-agent 2>/dev/null || true

# Stop karabiner_grabber to release exclusive HID access before Kanata starts
print_status "Stopping karabiner_grabber to release HID device..."
# Use sudo -n to avoid hanging on password prompts
sudo -n killall karabiner_grabber 2>/dev/null || true
sleep 1

EXIT_CODE=0

# Reload Main Instance
reload_instance "local.kanata" "local.kanata-vk-agent" "5829" || EXIT_CODE=1

# Reload Charybdis Instance
reload_instance "local.kanata-charibdis" "local.kanata-vk-agent-charibdis" "5830" || EXIT_CODE=1

if [ "$EXIT_CODE" = 1 ]; then
    print_error "Reload complete with ERRORS!"
    exit 1
fi

print_status "Reload complete!"
exit 0
