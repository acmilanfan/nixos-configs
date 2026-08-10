#!/bin/bash
# Discover Yoga Book 9i Bluetooth keyboard device name for kanata config
# Run this to find your keyboard's device name

echo "Scanning for BT keyboards..."
echo "------------------------------"

found=""
while IFS= read -r line; do
    case "$line" in
        I:*)
            bus="${line#I: Bus=}"
            bus="${bus%% *}"
            ;;
        N:*)
            name="${line#N: Name=\"}"
            name="${name%%\"*}"
            ;;
        H:*kbd*)
            if [ -n "$name" ]; then
                case "$name" in
                    *"INGENIC Gadget"*|*"Aurora Sweep"*|*"Charybdis"*|*"Power Button"*|*"Sleep Button"*|*"Video Bus"*|*"Lid Switch"*)
                        echo "  SKIPPED: $name (excluded)"
                        ;;
                    *)
                        echo "  → FOUND:  $name (Bus: $bus)"
                        echo ""
                        echo "Add this name to your kanata config:"
                        echo "  linux-dev-names-include ("
                        echo "    \"$name\""
                        echo "  )"
                        found="$name"
                        ;;
                esac
            fi
            name=""
            ;;
    esac
done < /proc/bus/input/devices 2>/dev/null

if [ -z "$found" ]; then
    echo ""
    echo "No Yoga Book keyboard found. Make sure:"
    echo "  1. The keyboard is connected via Bluetooth"
    echo "  2. The keyboard is powered on and paired"
    echo ""
    echo "If you just connected the keyboard, wait a few seconds and try again."
fi
