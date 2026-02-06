#!/bin/bash

# Unified Kanata Reload Script
# Reloads both Main and Charybdis instances

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

USER_ID=$(id -u)

reload_instance() {
    local DAEMON_LABEL=$1
    local AGENT_LABEL=$2
    local DAEMON_PLIST="/Library/LaunchDaemons/${DAEMON_LABEL}.plist"
    local AGENT_PLIST="/Library/LaunchAgents/${AGENT_LABEL}.plist"
    local LOG_FILE=$3

    print_status "--- Reloading $DAEMON_LABEL ---"

    # 1. Restart Daemon (Root)
    if sudo launchctl list | grep -q "$DAEMON_LABEL"; then
        sudo launchctl bootout system/"$DAEMON_LABEL" 2>/dev/null || true
    fi

    if [[ -f "$DAEMON_PLIST" ]]; then
        sudo launchctl bootstrap system "$DAEMON_PLIST"
        print_status "Daemon $DAEMON_LABEL bootstrapped."
    else
        print_warning "Plist not found at $DAEMON_PLIST"
    fi

    # 2. Restart VK Agent (User)
    if launchctl print gui/"$USER_ID"/"$AGENT_LABEL" &>/dev/null; then
        launchctl bootout gui/"$USER_ID"/"$AGENT_LABEL" 2>/dev/null || true
    fi

    if [[ -f "$AGENT_PLIST" ]]; then
        launchctl bootstrap gui/"$USER_ID" "$AGENT_PLIST"
        print_status "VK Agent $AGENT_LABEL bootstrapped."
    else
        print_warning "VK Agent Plist not found at $AGENT_PLIST"
    fi

    # 3. Verify
    sleep 1
    if sudo launchctl list | grep -q "$DAEMON_LABEL"; then
        print_status "✓ $DAEMON_LABEL is running"
    else
        print_error "✗ $DAEMON_LABEL failed to start"
    fi
}

print_status "Starting Kanata system-wide reload..."

# Reload Main Instance
reload_instance "org.nixos.kanata" "local.kanata-vk-agent" "/Users/andreishumailov/.config/kanata/kanata.log"

# Reload Charybdis Instance
reload_instance "org.nixos.kanata-charibdis" "local.kanata-vk-agent-charibdis" "/Users/andreishumailov/.config/kanata/kanata-charibdis.log"

print_status "All Kanata services reloaded!"