#!/bin/bash

# Optimized Unified Kanata Reload Script
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

# Function to restart a service quickly or bootstrap if needed
restart_service() {
    local DOMAIN=$1
    local LABEL=$2
    local PLIST=$3
    local SUDO=$4

    if [[ "$SUDO" == "sudo" ]]; then
        if sudo launchctl list "$LABEL" >/dev/null 2>&1; then
            print_status "Kickstarting $LABEL ($DOMAIN)..."
            sudo launchctl kickstart -k "$DOMAIN"/"$LABEL"
        elif [[ -f "$PLIST" ]]; then
            print_status "Bootstrapping $LABEL ($DOMAIN)..."
            sudo launchctl bootstrap "$DOMAIN" "$PLIST"
        fi
    else
        if launchctl list "$LABEL" >/dev/null 2>&1; then
            print_status "Kickstarting $LABEL ($DOMAIN)..."
            launchctl kickstart -k "$DOMAIN"/"$LABEL"
        elif [[ -f "$PLIST" ]]; then
            print_status "Bootstrapping $LABEL ($DOMAIN)..."
            launchctl bootstrap "$DOMAIN" "$PLIST"
        fi
    fi
}

reload_instance() {
    local KANATA_LABEL=$1
    local AGENT_LABEL=$2
    local PORT=$3

    print_status "--- Reloading $KANATA_LABEL and $AGENT_LABEL (Port $PORT) ---"

    # Boot out Karabiner services that interfere with kanata's HID exclusive access.
    # killall/pkill is not enough — launchd KeepAlive restarts them within milliseconds.
    # bootout removes them from the current launchd session entirely until next reboot.
    # Order matters: bootout session_monitor first so it can't restart grabber.
    print_status "Booting out Karabiner services..."
    launchctl bootout "gui/$USER_ID" org.pqrs.service.agent.karabiner_session_monitor 2>/dev/null || true
    launchctl bootout "gui/$USER_ID" org.pqrs.service.agent.karabiner_console_user_server 2>/dev/null || true
    launchctl bootout "gui/$USER_ID" org.pqrs.service.agent.karabiner_grabber 2>/dev/null || true
    sudo -n launchctl bootout system org.pqrs.service.daemon.karabiner_grabber 2>/dev/null || true

    # Restart Kanata (System domain)
    restart_service "system" "$KANATA_LABEL" "/Library/LaunchDaemons/${KANATA_LABEL}.plist" "sudo"

    # Restart Agent (User domain)
    restart_service "gui/$USER_ID" "$AGENT_LABEL" "/Library/LaunchAgents/${AGENT_LABEL}.plist" ""

    # Wait for the actual kanata binary to be running.
    # Must match the binary path (not the bash wrapper whose argv contains the path as a string).
    # pgrep -f without anchoring matches the bash wrapper immediately — which is the bug.
    local SUCCESS=false
    for i in {1..20}; do
        if pgrep -f "^/opt/homebrew/bin/kanata.*--port $PORT" >/dev/null; then
            SUCCESS=true
            break
        fi
        sleep 0.2
    done

    if [ "$SUCCESS" = true ]; then
        print_status "✓ Instance $PORT reloaded successfully"
        return 0
    else
        print_error "✗ Instance $PORT failed to start correctly"
        return 1
    fi
}

print_status "Starting Optimized Kanata reload..."

EXIT_CODE=0

# Boot out Charybdis BEFORE starting Main so Main wins the IOKit exclusive-access race.
# Both instances seize ALL HID devices (including Apple Internal Keyboard) regardless of
# macos-dev-names-include. If Charybdis is alive when Main tries to start, Main loses the
# race and never intercepts keyboard events — home row mods silently break.
if sudo launchctl list "local.kanata-charibdis" >/dev/null 2>&1; then
    print_status "Booting out Charybdis first (prevents keyboard race)..."
    # Try bootout first; on some macOS versions it fails with EIO — fall back to unload.
    if ! sudo launchctl bootout system "local.kanata-charibdis" 2>/dev/null; then
        sudo launchctl unload /Library/LaunchDaemons/local.kanata-charibdis.plist 2>/dev/null || true
    fi
fi

# Reload Main Instance (now has uncontested access to Apple Internal Keyboard)
reload_instance "local.kanata" "local.kanata-vk-agent" "5829" || EXIT_CODE=1

# Reload Charybdis Instance (only if needed/configured)
if [[ -f "/Library/LaunchDaemons/local.kanata-charibdis.plist" ]]; then
    reload_instance "local.kanata-charibdis" "local.kanata-vk-agent-charibdis" "5830" || EXIT_CODE=1
fi

if [ "$EXIT_CODE" = 0 ]; then
    print_status "Reload complete!"
    if [[ "$*" == *"--show-logs"* ]]; then
        print_status "Showing logs (Ctrl+C to stop)..."
        tail -f /tmp/kanata.log
    fi
    exit 0
else
    print_error "Reload complete with ERRORS!"
    exit 1
fi
