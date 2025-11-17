#!/bin/bash

# AeroSpace Window Border Daemon
#
# This daemon polls the system state to manage JankyBorders.
# It disables borders when:
#   1. A window on the focused workspace is maximized (AeroSpace "fullscreen").
#   2. There is only one window on the focused workspace.

# --- JankyBorders Configuration ---
ACTIVE_COLOR="0xff007acc"
INACTIVE_COLOR="0x00000000"
BORDER_WIDTH=2.0
BLACKLIST="Finder,System Preferences,Activity Monitor,Calculator,Archive Utility,Maccy"
# --- End Configuration ---

# --- Daemon Configuration ---
DAEMON_NAME="aero-border-daemon"
PID_FILE="/tmp/${DAEMON_NAME}.pid"
LOG_FILE="/tmp/${DAEMON_NAME}.log"
CHECK_INTERVAL=2  # How often to check the state, in seconds.
# --- End Daemon Configuration ---

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to check if JankyBorders is running
is_borders_running() {
    pgrep -x "borders" > /dev/null
}

# Function to start JankyBorders
start_jankyborders() {
    if ! is_borders_running; then
        log_message "Starting JankyBorders"
        borders \
            active_color="$ACTIVE_COLOR" \
            inactive_color="$INACTIVE_COLOR" \
            width="$BORDER_WIDTH" \
            hidpi=on \
            style=round \
            blacklist="$BLACKLIST" &
    fi
}

# Function to stop JankyBorders
stop_jankyborders() {
    if is_borders_running; then
        log_message "Stopping JankyBorders"
        killall borders
    fi
}

# The core logic function that runs in the loop
update_border_state() {
    # Get the name of the currently focused workspace
    local focused_workspace
    focused_workspace=$(aerospace list-workspaces --focused 2>/dev/null)

    if [[ -z "$focused_workspace" ]]; then
        log_message "Error: Could not get focused workspace. AeroSpace might not be running."
        # Stop borders as a safe fallback
        stop_jankyborders
        return
    fi

    # 1. Check if any window on the focused workspace is maximized (AeroSpace fullscreen)
    # The --fullscreen flag lists *only* maximized windows.
    # We check if the command produced *any* output.
    local is_maximized=false
    if aerospace list-windows --workspace "$focused_workspace" --fullscreen 2>/dev/null | grep -q .; then
        is_maximized=true
    fi

    # 2. Count the total number of windows on the focused workspace
    local window_count
    window_count=$(aerospace list-windows --workspace "$focused_workspace" 2>/dev/null | wc -l)

    # 3. Your Logic: Hide borders if maximized OR if only one window
    if [[ "$is_maximized" == true || "$window_count" -le 1 ]]; then
        # We should NOT have borders
        stop_jankyborders
    else
        # We SHOULD have borders
        start_jankyborders
    fi
}

# --- Main Daemon Execution ---

case "${1:-start}" in
    "start")
        if [[ -f "$PID_FILE" ]]; then
            echo "Daemon is already running (PID: $(cat "$PID_FILE"))."
            exit 1
        fi
        echo "Starting border daemon... Log at $LOG_FILE"
        # Create PID file with the daemon's PID
        echo $$ > "$PID_FILE"
        log_message "Daemon started (PID: $$)"

        # Main loop
        while true; do
            # Check if we should still be running
            if [[ ! -f "$PID_FILE" ]] || [[ "$(cat "$PID_FILE")" != "$$" ]]; then
                log_message "PID file missing or changed. Exiting loop."
                break
            fi

            update_border_state
            sleep "$CHECK_INTERVAL"
        done & # Run the loop in the background
        ;;

    "stop")
        if [[ -f "$PID_FILE" ]]; then
            pid=$(cat "$PID_FILE")
            echo "Stopping daemon (PID: $pid)..."
            # Kill the daemon process
            kill "$pid" 2>/dev/null
            rm -f "$PID_FILE"
            # Also stop borders when the daemon stops
            stop_jankyborders
            log_message "Daemon stopped"
            echo "Daemon stopped."
        else
            echo "Daemon not running."
        fi
        ;;

    "restart")
        "$0" stop
        sleep 0.5
        "$0" start
        ;;

    "status")
        if [[ -f "$PID_FILE" ]]; then
            echo "Daemon is running (PID: $(cat "$PID_FILE"))."
            if is_borders_running; then
                echo "JankyBorders is currently ON."
            else
                echo "JankyBorders is currently OFF."
            fi
        else
            echo "Daemon is not running."
        fi
        ;;

    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
