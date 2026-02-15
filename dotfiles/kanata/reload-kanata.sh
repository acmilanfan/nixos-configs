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
CURRENT_USER=$(id -un)

reload_instance() {
    local DAEMON_LABEL=$1
    local AGENT_LABEL=$2
    local LOG_FILE=$3

    print_status "--- Reloading $DAEMON_LABEL and $AGENT_LABEL ---"

    # 1. Restart Daemon (Root)
    # We try to use sudo -n (non-interactive) first
    if sudo -n true 2>/dev/null; then
        print_status "Restarting system daemon $DAEMON_LABEL..."
        if sudo launchctl list | grep -q "$DAEMON_LABEL"; then
            sudo launchctl bootout system/"$DAEMON_LABEL" 2>/dev/null || true
        fi

        # Find the plist - nix-darwin usually puts it in /Library/LaunchDaemons/
        local DAEMON_PLIST="/Library/LaunchDaemons/${DAEMON_LABEL}.plist"
        if [[ -f "$DAEMON_PLIST" ]]; then
            sudo launchctl bootstrap system "$DAEMON_PLIST"
            print_status "Daemon $DAEMON_LABEL bootstrapped."
        else
            # Try fallback location or just use pkill if enabled
            print_warning "Daemon plist not found at $DAEMON_PLIST, trying pkill..."
            sudo pkill -f "kanata.*$DAEMON_LABEL" || true
        fi
    else
        print_warning "Sudo password required for daemon reload. Attempting to kill process instead..."
        # If we can't sudo launchctl, maybe we can pkill if it's running as user (unlikely)
        # or just inform the user.
        print_warning "Skipping daemon $DAEMON_LABEL restart (no sudo access)."
        print_warning "Please run 'reload-kanata' from terminal to refresh the system-wide daemon."
    fi

    # 2. Restart VK Agent (User)
    # This shouldn't require sudo
    print_status "Restarting user agent $AGENT_LABEL..."
    if launchctl print gui/"$USER_ID"/"$AGENT_LABEL" &>/dev/null; then
        launchctl bootout gui/"$USER_ID"/"$AGENT_LABEL" 2>/dev/null || true
        sleep 0.5
    fi

    # Find the agent plist - nix-darwin puts it in /Library/LaunchAgents/
    local AGENT_PLIST="/Library/LaunchAgents/${AGENT_LABEL}.plist"
    if [[ -f "$AGENT_PLIST" ]]; then
        launchctl bootstrap gui/"$USER_ID" "$AGENT_PLIST"
        print_status "VK Agent $AGENT_LABEL bootstrapped."
    else
        # Try ~/Library/LaunchAgents/
        local USER_AGENT_PLIST="$HOME/Library/LaunchAgents/${AGENT_LABEL}.plist"
        if [[ -f "$USER_AGENT_PLIST" ]]; then
            launchctl bootstrap gui/"$USER_ID" "$USER_AGENT_PLIST"
            print_status "VK Agent $AGENT_LABEL bootstrapped from user directory."
        else
            print_error "VK Agent Plist not found for $AGENT_LABEL"
        fi
    fi

    # 3. Verify
    sleep 1
    if pgrep -f "$AGENT_LABEL" >/dev/null; then
        print_status "✓ $AGENT_LABEL is running"
    else
        print_error "✗ $AGENT_LABEL failed to start"
    fi
}

print_status "Starting Kanata system-wide reload..."

# Reload Main Instance
# Note: The labels must match what's in darwin/common.nix
# In nix-darwin, the daemon label is usually org.nixos.kanata
reload_instance "org.nixos.kanata" "local.kanata-vk-agent" "$HOME/.config/kanata/kanata.log"

# Reload Charybdis Instance
reload_instance "org.nixos.kanata-charibdis" "local.kanata-vk-agent-charibdis" "$HOME/.config/kanata/kanata-charibdis.log"

print_status "Reload complete!"
