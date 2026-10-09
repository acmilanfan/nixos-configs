#!/bin/bash

# Kanata Configuration Widget for SketchyBar
# Shows current mode and allows switching via popup

ACTIVE_CONFIG="$HOME/.config/kanata/active_config.kbd"
SWITCH_SCRIPT="$HOME/.config/kanata/switch-kanata.sh"
# Root operations: kanata-ctl is the one command sudoers allows NOPASSWD
# (darwin/common.nix). -n: fail instead of hanging on a prompt.
KANATA_CTL="sudo -n /run/current-system/sw/bin/kanata-ctl"

update() {
    local target
    if [ -L "$ACTIVE_CONFIG" ]; then
        target=$(readlink "$ACTIVE_CONFIG")
    else
        target="unknown"
    fi

    local icon="󰌌"
    local label="Unknown"
    local color=0xffc0caf5 # WHITE

    case "$target" in
        *kanata-default.kbd)
            label="Standard"
            icon="󰌌"
            color=0xff9ece6a # Green
            ;;
        *kanata-homerow.kbd | *kanata.kbd)
            label="Homerow"
            icon="󰓁"
            color=0xff7b5cff # Purple
            ;;
        *kanata-split.kbd | *kanata-split-fixed.kbd)
            label="Split"
            icon="󰗵"
            color=0xffe0af68 # Yellow
            ;;
        *kanata-angle.kbd)
            label="Angle"
            icon="󰓁"
            color=0xff7dcfff # Cyan
            ;;
        *kanata-disabled.kbd)
            label="Disabled"
            icon="󰅛"
            color=0xfff7768e # Red
            ;;
        *kanata-training.kbd | *kanata-training-iso.kbd)
            label="Training"
            icon="󰮡"
            color=0xffff9e64 # Orange
            ;;
    esac

    # Always update the main 'kanata' item, regardless of which popup item triggered the script
    sketchybar --set kanata icon="$icon" icon.color="$color"
}

popup() {
    sketchybar --set kanata popup.drawing=toggle
}

switch_mode() {
    local mode="$1"
    if [ -f "$SWITCH_SCRIPT" ]; then
        # Feedback: Loading state
        sketchybar --set kanata icon="󱑊" icon.color=0xffe0af68 popup.drawing=off

        # Run switch (this script will trigger 'kanata_changed' event)
        bash "$SWITCH_SCRIPT" "$mode" > /tmp/sketchybar_kanata_switch.log 2>&1

        # No need to call update or sleep here;
        # the 'kanata_changed' event triggered by switch-kanata.sh will handle it.
    fi
}

case "$SENDER" in
    "routine" | "forced" | "kanata_changed")
        update
        ;;
    "mouse.clicked")
        if [ "$BUTTON" = "left" ]; then
            popup
        fi
        ;;
    "kanata_switch_default")
        switch_mode "default"
        ;;
    "kanata_switch_homerow")
        switch_mode "homerow"
        ;;
    "kanata_switch_split")
        switch_mode "split"
        ;;
    "kanata_switch_angle")
        switch_mode "angle"
        ;;
    "kanata_switch_disabled")
        switch_mode "disabled"
        ;;
    "kanata_switch_training")
        switch_mode "training"
        ;;
    "kanata_rescue_kill")
        sketchybar --set kanata popup.drawing=off
        # Emergency: kill everything that could be blocking keyboard input
        # (grabber, kanata, VirtualHID daemon+dext), then bring the VirtualHID
        # daemon and kanata back. kanata-ctl matches kanata-nix exactly; the old
        # `pkill -f kanata` also killed this script before it restarted anything.
        echo "$(date): Emergency kill triggered" >> /tmp/sketchybar_kanata_rescue.log
        $KANATA_CTL rescue >> /tmp/sketchybar_kanata_rescue.log 2>&1 || true
        ;;
    "kanata_rescue_reload")
        sketchybar --set kanata popup.drawing=off
        # Full reload via the smart health-check script. Pass --force to skip checks
        # and always restart. The reload script now detects TCC denial and handles
        # dext lock by force-restarting the VirtualHID daemon before restarting kanata.
        if [ -f "$HOME/.config/kanata/reload-kanata.sh" ]; then
            bash "$HOME/.config/kanata/reload-kanata.sh" --force >> /tmp/sketchybar_kanata_rescue.log 2>&1 &
        fi
        ;;
    "kanata_rescue_restore_hid")
        sketchybar --set kanata popup.drawing=off
        # Force-restart the entire Karabiner driver stack to release locked HID devices.
        # The grabber's dext holds exclusive IOHIDDeviceOpen; killing just the daemon
        # with kickstart -k may not be enough if the grabber re-opens devices faster
        # than they're released. Kill all karabiner processes first, then restart.
        echo "$(date): Restore Virtual HID triggered" >> /tmp/sketchybar_kanata_rescue.log
        $KANATA_CTL neutralize || true
        $KANATA_CTL reset-hid || true
        sleep 1
        # If kanata was running before the HID lock, restart it now that devices are released
        $KANATA_CTL restart || true
        ;;
esac
