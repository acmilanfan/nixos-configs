#!/bin/bash

# Kanata Configuration Reload Script
# This script reloads the Kanata configuration by restarting the launchd agents

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
KANATA_AGENT="org.nixos.kanata"
KANATA_VK_AGENT="local.kanata-vk-agent"
CONFIG_FILE="/Users/andreishumailov/.config/kanata/kanata.kbd"

print_status "Starting Kanata configuration reload..."

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    print_error "Kanata configuration file not found at: $CONFIG_FILE"
    exit 1
fi

print_status "Configuration file found: $CONFIG_FILE"

# Function to stop a launchd agent (nix-darwin managed)
stop_agent() {
    local agent_name="$1"
    print_status "Stopping $agent_name..."

    if sudo launchctl list | grep -q "$agent_name"; then
        sudo launchctl stop "$agent_name" 2>/dev/null || true
        sudo launchctl unload "/Library/LaunchAgents/${agent_name}.plist" 2>/dev/null || true
        print_status "$agent_name stopped"
    else
        print_warning "$agent_name was not running"
    fi
}

# Function to start a launchd agent (nix-darwin managed)
start_agent() {
    local agent_name="$1"
    print_status "Starting $agent_name..."

    if [[ -f "/Library/LaunchAgents/${agent_name}.plist" ]]; then
        sudo launchctl load "/Library/LaunchAgents/${agent_name}.plist"
        sudo launchctl start "$agent_name"
        print_status "$agent_name started"
    else
        print_warning "Launch agent plist not found for $agent_name at /Library/LaunchAgents/"
    fi
}

# Stop both agents
stop_agent "$KANATA_AGENT"
stop_agent "$KANATA_VK_AGENT"

# Wait a moment for processes to fully stop
sleep 2

# Start both agents
start_agent "$KANATA_AGENT"
start_agent "$KANATA_VK_AGENT"

# Wait a moment for services to start
sleep 2

# Check if services are running
print_status "Checking service status..."

if sudo launchctl list | grep -q "$KANATA_AGENT"; then
    print_status "✓ $KANATA_AGENT is running"
else
    print_error "✗ $KANATA_AGENT failed to start"
fi

if sudo launchctl list | grep -q "$KANATA_VK_AGENT"; then
    print_status "✓ $KANATA_VK_AGENT is running"
else
    print_error "✗ $KANATA_VK_AGENT failed to start"
fi

print_status "Kanata configuration reload completed!"

# Optional: Show recent log entries
if [[ "$1" == "--show-logs" ]]; then
    print_status "Recent Kanata logs:"
    tail -n 10 /Users/andreishumailov/.config/kanata/kanata.log 2>/dev/null || print_warning "Could not read kanata.log"
fi

