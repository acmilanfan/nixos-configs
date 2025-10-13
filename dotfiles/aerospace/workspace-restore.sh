#!/bin/bash

# AeroSpace Workspace Restore Script
# This script helps restore workspace state after screen lock/unlock cycles
# It can be run manually or automatically via system events

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> ~/Library/Logs/aerospace-restore.log
}

# Function to check if AeroSpace is running
is_aerospace_running() {
    pgrep -x "AeroSpace" > /dev/null
}

# Function to reload AeroSpace configuration
reload_aerospace() {
    if is_aerospace_running; then
        log_message "Reloading AeroSpace configuration..."
        aerospace reload-config
        sleep 1
    else
        log_message "AeroSpace is not running, starting it..."
        open -a AeroSpace
        sleep 2
    fi
}

# Function to flatten workspace tree (reset layout issues)
flatten_workspaces() {
    if is_aerospace_running; then
        log_message "Flattening workspace tree to fix layout issues..."
        aerospace flatten-workspace-tree
    fi
}

# Function to ensure workspaces exist
ensure_workspaces() {
    if is_aerospace_running; then
        log_message "Ensuring all workspaces are available..."
        # Create workspaces 1-20 by briefly switching to them
        for i in {1..20}; do
            aerospace workspace $i > /dev/null 2>&1
            sleep 0.1
        done
        # Return to workspace 1
        aerospace workspace 1 > /dev/null 2>&1
    fi
}

# Function to fix window focus issues
fix_focus() {
    if is_aerospace_running; then
        log_message "Fixing window focus issues..."
        # Focus the current workspace to refresh focus
        current_workspace=$(aerospace list-workspaces --focused)
        if [ ! -z "$current_workspace" ]; then
            aerospace workspace "$current_workspace"
        fi
    fi
}

# Main restoration function
restore_workspace_state() {
    log_message "Starting workspace restoration process..."
    
    # Wait a moment for system to stabilize after wake
    sleep 2
    
    # Reload configuration
    reload_aerospace
    
    # Ensure all workspaces exist
    ensure_workspaces
    
    # Flatten any problematic layouts
    flatten_workspaces
    
    # Fix focus issues
    fix_focus
    
    log_message "Workspace restoration completed"
}

# Check command line arguments
case "${1:-}" in
    "restore")
        restore_workspace_state
        ;;
    "reload")
        reload_aerospace
        ;;
    "flatten")
        flatten_workspaces
        ;;
    "focus")
        fix_focus
        ;;
    *)
        echo "Usage: $0 {restore|reload|flatten|focus}"
        echo "  restore - Full workspace restoration (recommended after screen unlock)"
        echo "  reload  - Reload AeroSpace configuration"
        echo "  flatten - Flatten workspace tree to fix layout issues"
        echo "  focus   - Fix window focus issues"
        exit 1
        ;;
esac
