#!/bin/bash

# Unified Kanata Reload Script
# Reloads both Main and Charybdis instances

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

USER_ID=$(id -u)

# Function to ensure sudo access (only for things that still might need it,
# although kanata agents now use internal sudo with NOPASSWD)
ensure_sudo() {
    if ! sudo -n true 2>/dev/null; then
        print_warning "Sudo access required for some operations."
        print_status "Please enter your password:"
        if ! sudo true; then
            print_error "Failed to acquire sudo privileges."
            return 1
        fi
    fi
    return 0
}

reload_instance() {
    local KANATA_LABEL=$1
    local AGENT_LABEL=$2
    local PORT=$3

    print_status "--- Reloading $KANATA_LABEL and $AGENT_LABEL (Port $PORT) ---"

    # 1. Restart Kanata (User Agent with internal sudo)
    if launchctl print gui/"$USER_ID"/"$KANATA_LABEL" &>/dev/null; then
        launchctl bootout gui/"$USER_ID"/"$KANATA_LABEL" 2>/dev/null || true
        sleep 0.5
    fi

    local KANATA_PLIST="/Library/LaunchAgents/${KANATA_LABEL}.plist"
    if [[ -f "$KANATA_PLIST" ]]; then
        launchctl bootstrap gui/"$USER_ID" "$KANATA_PLIST"
        print_status "Kanata $KANATA_LABEL bootstrapped."
    else
        print_warning "Kanata plist not found at $KANATA_PLIST"
    fi

    # 2. Restart VK Agent (User Agent)
    if launchctl print gui/"$USER_ID"/"$AGENT_LABEL" &>/dev/null; then
        launchctl bootout gui/"$USER_ID"/"$AGENT_LABEL" 2>/dev/null || true
        sleep 1
    fi

    local AGENT_PLIST="/Library/LaunchAgents/${AGENT_LABEL}.plist"
    if [[ -f "$AGENT_PLIST" ]]; then
        launchctl bootstrap gui/"$USER_ID" "$AGENT_PLIST"
        print_status "VK Agent $AGENT_LABEL bootstrapped."
    else
        print_error "VK Agent Plist not found at $AGENT_PLIST"
    fi

    # 3. Verify
    sleep 2
    if pgrep -f "kanata.*--port $PORT" >/dev/null; then
        print_status "✓ Kanata ($PORT) is running"
    else
        print_error "✗ Kanata ($PORT) failed to start"
    fi

    if pgrep -f "kanata-vk-agent.*-p $PORT" >/dev/null; then
        print_status "✓ $AGENT_LABEL is running"
    else
        print_error "✗ $AGENT_LABEL failed to start"
    fi
}

print_status "Starting Kanata system-wide reload..."

# Stop karabiner_grabber to release exclusive HID access before Kanata starts
print_status "Stopping karabiner_grabber to release HID device..."
sudo killall karabiner_grabber 2>/dev/null || true
sleep 0.5

# Reload Main Instance
reload_instance "local.kanata" "local.kanata-vk-agent" "5829"

# Reload Charybdis Instance
reload_instance "local.kanata-charibdis" "local.kanata-vk-agent-charibdis" "5830"

print_status "Reload complete!"
