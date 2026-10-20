#!/usr/bin/env bash

# Robust ssh-add script for graphical login
LOG_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/ssh-add-login.log"
mkdir -p "$(dirname "$LOG_FILE")"
echo "Starting ssh-add-login at $(date)" > "$LOG_FILE"

# Wait for session to be ready
sleep 10

# Ensure environment variables are set
export SSH_ASKPASS="/etc/profiles/per-user/$USER/bin/ssh-askpass"
export SSH_ASKPASS_REQUIRE=force
# Try to detect display
if [ -n "$WAYLAND_DISPLAY" ]; then
    echo "Wayland detected: $WAYLAND_DISPLAY" >> "$LOG_FILE"
elif [ -z "$DISPLAY" ]; then
    export DISPLAY=:0
    echo "Setting default DISPLAY=:0" >> "$LOG_FILE"
fi

echo "Checking for existing ssh-add processes..." >> "$LOG_FILE"
export SSH_AUTH_SOCK="$HOME/.ssh/ssh_auth_sock"
if pgrep -u "$USER" -x ssh-add > /dev/null; then
    echo "ssh-add already running, exiting." >> "$LOG_FILE"
    exit 0
fi

echo "Running ssh-add..." >> "$LOG_FILE"
# Pipe /dev/null to force usage of SSH_ASKPASS
ssh-add ~/.ssh/id_ed25519 < /dev/null >> "$LOG_FILE" 2>&1
rc=$?

if [ "$rc" -eq 0 ]; then
    echo "ssh-add successful." >> "$LOG_FILE"
else
    echo "ssh-add failed with exit code $rc." >> "$LOG_FILE"
fi
