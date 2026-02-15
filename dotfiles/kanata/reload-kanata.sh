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

reload_instance() {
    local DAEMON_LABEL=$1
    local AGENT_LABEL=$2
    local PORT=$3

    print_status "--- Reloading $DAEMON_LABEL (Port $PORT) ---"

    # 1. Restart Daemon (Root)
    if sudo -n true 2>/dev/null; then
        if sudo launchctl list | grep -q "$DAEMON_LABEL"; then
            sudo launchctl bootout system/"$DAEMON_LABEL" 2>/dev/null || true
        fi

        local DAEMON_PLIST="/Library/LaunchDaemons/${DAEMON_LABEL}.plist"
        if [[ -f "$DAEMON_PLIST" ]]; then
            sudo launchctl bootstrap system "$DAEMON_PLIST"
            print_status "Daemon $DAEMON_LABEL bootstrapped."
        else
            print_warning "Daemon plist not found at $DAEMON_PLIST"
        fi
    else
        print_warning "Sudo access not available (non-interactive). Skipping daemon restart."
        print_warning "To restart the daemon, run this script manually from a terminal."
    fi

    # 2. Restart VK Agent (User)
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
    if pgrep -f "kanata-vk-agent.*-p $PORT" >/dev/null; then
        print_status "✓ $AGENT_LABEL is running"
    else
        # Fallback check if port matching fails
        if launchctl print gui/"$USER_ID"/"$AGENT_LABEL" &>/dev/null; then
             print_status "✓ $AGENT_LABEL is registered with launchd"
        else
             print_error "✗ $AGENT_LABEL failed to start"
        fi
    fi
}

print_status "Starting Kanata system-wide reload..."

# Reload Main Instance
reload_instance "org.nixos.kanata" "local.kanata-vk-agent" "5829"

# Reload Charybdis Instance
reload_instance "org.nixos.kanata-charibdis" "local.kanata-vk-agent-charibdis" "5830"

print_status "Reload complete!"