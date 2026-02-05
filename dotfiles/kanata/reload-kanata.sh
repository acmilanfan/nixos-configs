#!/bin/bash

# Kanata Configuration Reload Script
# Updated for System Daemon (Root) and correct VK Agent Label

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
KANATA_LABEL="org.nixos.kanata"
KANATA_PLIST="/Library/LaunchDaemons/${KANATA_LABEL}.plist"

VK_AGENT_LABEL="local.kanata-vk-agent"
VK_AGENT_PLIST="/Library/LaunchAgents/${VK_AGENT_LABEL}.plist"

CONFIG_FILE="/Users/andreishumailov/.config/kanata/active_config.kbd"

print_status "Starting Kanata configuration reload..."

# 1. Check Config
if [[ ! -f "$CONFIG_FILE" ]]; then
    print_error "Kanata configuration file not found at: $CONFIG_FILE"
    exit 1
fi

# 2. Restart Kanata Daemon (Root)
print_status "Restarting Kanata Daemon..."
if sudo launchctl list | grep -q "$KANATA_LABEL"; then
    sudo launchctl bootout system/"$KANATA_LABEL" 2>/dev/null || true
fi

if [[ -f "$KANATA_PLIST" ]]; then
    sudo launchctl bootstrap system "$KANATA_PLIST"
    print_status "Kanata Daemon bootstrapped."
else
    print_error "Kanata Plist not found at $KANATA_PLIST. Run darwin-rebuild switch first."
    exit 1
fi

# 3. Restart VK Agent (User Agent)
print_status "Restarting VK Agent..."
# Note: User agents are bootstrapped into 'gui/501' (your user ID), not 'system'
USER_ID=$(id -u)
if launchctl print gui/"$USER_ID"/"$VK_AGENT_LABEL" &>/dev/null; then
    launchctl bootout gui/"$USER_ID"/"$VK_AGENT_LABEL" 2>/dev/null || true
fi

if [[ -f "$VK_AGENT_PLIST" ]]; then
    launchctl bootstrap gui/"$USER_ID" "$VK_AGENT_PLIST"
    print_status "VK Agent bootstrapped."
else
    print_warning "VK Agent Plist not found at $VK_AGENT_PLIST."
fi

# 4. Wait and Verify
sleep 2
print_status "Checking service status..."

if sudo launchctl list | grep -q "$KANATA_LABEL"; then
    print_status "✓ $KANATA_LABEL is running"
else
    print_error "✗ $KANATA_LABEL failed to start"
fi

# Check logs for the specific driver success message
if grep -q "driver connected: true" /Users/andreishumailov/.config/kanata/kanata.log; then
     print_status "✓ Driver connected successfully"
else
     print_warning "⚠ Driver connection not confirmed in logs yet. Check permissions."
fi

print_status "Reload completed!"
