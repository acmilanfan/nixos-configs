#!/bin/bash
# Waybar module: shows kanata profile when Yoga Book 9i BT keyboard is connected
# Hidden when external keyboards (Sweep, Charybdis) or no BT keyboard is connected

ACTIVE_CONFIG="$HOME/.config/kanata/active_config.kbd"

# Check if Yoga Book BT keyboard is present.
# Returns 0 if found, 1 if not.
yogabook_keyboard_present() {
    local in_kbd=0 kbd_name=""
    while IFS= read -r line; do
        case "$line" in
            N:*)
                kbd_name="${line#N: Name=\"}"
                kbd_name="${kbd_name%%\"*}"
                ;;
            H:*kbd*)
                if [ -n "$kbd_name" ]; then
                    case "$kbd_name" in
                        *"Yoga Book 9 14 Bluetooth KB"*)
                            return 0
                            ;;
esac
                fi
                ;;
        esac
    done < /proc/bus/input/devices 2>/dev/null
    return 1
}

if ! yogabook_keyboard_present; then
    echo '{"text": "", "tooltip": "", "class": ""}'
    exit 0
fi

# Read current mode from active config symlink
if [ -L "$ACTIVE_CONFIG" ]; then
    target=$(readlink -f "$ACTIVE_CONFIG" 2>/dev/null || readlink "$ACTIVE_CONFIG")
else
    target=""
fi

case "$target" in
    *kanata-yogabook*|*kanatayogabook*|*kanata-homerow*)
        text=" HR"
        tooltip="Kanata: Home Row Mods (mouse layer on g)"
        class="kanata-homerow"
        ;;
    *kanata-disabled*)
        text=" OFF"
        tooltip="Kanata: Disabled (pass-through)"
        class="kanata-disabled"
        ;;
    *)
        text=" ?"
        tooltip="Kanata: Unknown config ($target)"
        class="kanata-unknown"
        ;;
esac

echo "{\"text\": \"$text\", \"tooltip\": \"$tooltip\", \"class\": \"$class\"}"
