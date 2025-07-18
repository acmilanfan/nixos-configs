#!/bin/bash

# Window highlighting daemon for AeroSpace
# This daemon monitors workspace changes and window count to dynamically enable/disable JankyBorders

# Source the main window highlighting script functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/window-highlight.sh"

# Daemon configuration
DAEMON_NAME="aerospace-window-highlight"
PID_FILE="/tmp/${DAEMON_NAME}.pid"
LOG_FILE="/tmp/${DAEMON_NAME}.log"
CHECK_INTERVAL=2  # Check every 2 seconds

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to check if daemon is already running
is_daemon_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0
        else
            rm -f "$PID_FILE"
            return 1
        fi
    fi
    return 1
}

# Function to stop the daemon
stop_daemon() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            kill "$pid"
            rm -f "$PID_FILE"
            log_message "Daemon stopped"
            echo "Window highlighting daemon stopped"
        else
            rm -f "$PID_FILE"
            echo "Daemon was not running"
        fi
    else
        echo "Daemon is not running"
    fi
}

# Function to update highlighting based on current state
update_highlighting_state() {
    local should_be_highlighted
    local is_currently_running
    
    # Check if highlighting should be enabled based on window count
    if should_highlight; then
        should_be_highlighted=true
    else
        should_be_highlighted=false
    fi
    
    # Check current JankyBorders status
    if is_running; then
        is_currently_running=true
    else
        is_currently_running=false
    fi
    
    # Update highlighting state if needed
    if [[ "$should_be_highlighted" == true ]] && [[ "$is_currently_running" == false ]]; then
        log_message "Starting JankyBorders - multiple windows detected"
        start_jankyborders
    elif [[ "$should_be_highlighted" == false ]] && [[ "$is_currently_running" == true ]]; then
        log_message "Stopping JankyBorders - single window detected"
        stop_jankyborders
    fi
}

# Main daemon loop
run_daemon() {
    # Create PID file
    echo $$ > "$PID_FILE"
    
    log_message "Window highlighting daemon started (PID: $$)"
    
    # Initial state update
    update_highlighting_state
    
    # Main monitoring loop
    while true; do
        # Check if we should still be running
        if [[ ! -f "$PID_FILE" ]] || [[ "$(cat "$PID_FILE")" != "$$" ]]; then
            log_message "Daemon PID file changed or removed, exiting"
            break
        fi
        
        # Update highlighting state
        update_highlighting_state
        
        # Wait before next check
        sleep "$CHECK_INTERVAL"
    done
    
    # Cleanup on exit
    rm -f "$PID_FILE"
    log_message "Daemon exited"
}

# Function to show daemon status
show_status() {
    if is_daemon_running; then
        local pid=$(cat "$PID_FILE")
        echo "Window highlighting daemon is running (PID: $pid)"
        
        # Show current highlighting state
        if is_running; then
            echo "JankyBorders is currently running"
        else
            echo "JankyBorders is currently stopped"
        fi
        
        # Show window count
        if command -v aerospace >/dev/null 2>&1; then
            local focused_workspace=$(aerospace list-workspaces --focused 2>/dev/null)
            if [[ -n "$focused_workspace" ]]; then
                local window_count=$(aerospace list-windows --workspace "$focused_workspace" --format '%{window-id}' 2>/dev/null | wc -l | xargs)
                echo "Current workspace: $focused_workspace (${window_count} windows)"
            fi
        fi
    else
        echo "Window highlighting daemon is not running"
    fi
}

# Main execution
case "${1:-start}" in
    "start")
        if is_daemon_running; then
            echo "Daemon is already running"
            exit 1
        else
            echo "Starting window highlighting daemon..."
            run_daemon &
            sleep 1
            show_status
        fi
        ;;
    "stop")
        stop_daemon
        ;;
    "restart")
        stop_daemon
        sleep 1
        echo "Starting window highlighting daemon..."
        run_daemon &
        sleep 1
        show_status
        ;;
    "status")
        show_status
        ;;
    "update")
        # Manual update trigger (for callbacks)
        update_highlighting_state
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|update}"
        echo "  start   - Start the window highlighting daemon"
        echo "  stop    - Stop the window highlighting daemon"
        echo "  restart - Restart the window highlighting daemon"
        echo "  status  - Show daemon status"
        echo "  update  - Manually trigger highlighting update"
        exit 1
        ;;
esac
