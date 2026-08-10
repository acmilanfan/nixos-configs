#!/bin/bash

ACTION="${1:-restart}"

case $ACTION in
    restart|--force)
        echo "Restarting kanata..."
        if systemctl --user is-active kanata &>/dev/null; then
            systemctl --user restart kanata
        elif systemctl is-active kanata &>/dev/null; then
            systemctl restart kanata
        else
            echo "Starting kanata..."
            systemctl --user start kanata 2>/dev/null || systemctl start kanata 2>/dev/null
        fi

        echo "Waiting for kanata to start..."
        for i in {1..10}; do
            if systemctl --user is-active kanata &>/dev/null || systemctl is-active kanata &>/dev/null; then
                echo "Kanata is running."
                exit 0
            fi
            sleep 0.5
        done

        echo "ERROR: Kanata failed to start. Check logs:"
        echo "  journalctl --user -u kanata -n 30"
        exit 1
        ;;
    status)
        if systemctl --user is-active kanata &>/dev/null; then
            echo "Kanata is running."
        elif systemctl is-active kanata &>/dev/null; then
            echo "Kanata is running (system service)."
        else
            echo "Kanata is NOT running."
        fi
        ;;
    logs|--show-logs)
        journalctl --user -u kanata -f -n 50
        ;;
    *)
        echo "Usage: $0 [restart|status|logs]"
        ;;
esac
