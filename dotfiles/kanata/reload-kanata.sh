#!/bin/bash

# Smart Kanata Health Check & Reload Script
# Only reloads if something is actually broken or environment changed
# Unless --force is passed, which performs a full ordered reset.

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

RELOAD_REQUIRED=false
REASON=""
FORCE=false

if [[ "$*" == *"--force"* ]]; then
    FORCE=true
    RELOAD_REQUIRED=true
    REASON="Manual force reload requested"
fi

# 1. Check if Main instance is running
if [ "$RELOAD_REQUIRED" = false ]; then
    if ! pgrep -f "^/usr/local/bin/kanata-nix.*--port 5829" >/dev/null; then
        RELOAD_REQUIRED=true
        REASON="Main Kanata instance is not running"
    fi
fi

# 2. Check if Karabiner Core is running (it shouldn't be, it steals HID access)
# NOTE: We do NOT check for VirtualHIDDevice-Daemon as it is required for Kanata.
if [ "$RELOAD_REQUIRED" = false ]; then
    if pgrep -x "Karabiner-Core-Service" >/dev/null || pgrep -x "karabiner_grabber" >/dev/null; then
        RELOAD_REQUIRED=true
        REASON="Karabiner grabber/service is active and might have stolen HID access"
    fi
fi

# 3. Check if karabiner_grabber was recently denied TCC on IOHIDDeviceOpen.
#    The grabber (if it managed to start) opens HID keyboards exclusively via the
#    DriverKit dext. When TCC Input Monitoring permission is missing/revoked,
#    macOS denies IOHIDDeviceOpen but the dext still holds exclusive access.
#    This creates a total keyboard blackout — even external keyboards stop working.
#    The grabber may have already been killed, but the dext lock persists until
#    the VirtualHIDDevice-Daemon (and its dext) is restarted.
if [ "$RELOAD_REQUIRED" = false ]; then
    if sudo /usr/bin/log show --predicate 'eventMessage CONTAINS "TCC deny IOHIDDeviceOpen" AND process == "karabiner_grabber"' --last 5m --style compact 2>/dev/null | grep -q "TCC deny"; then
        RELOAD_REQUIRED=true
        REASON="karabiner_grabber denied TCC on IOHIDDeviceOpen — HID devices may be locked by dext"
    fi
fi

# 4. Check if Kanata has lost Input Monitoring permission (TCC)
#    macOS ties Input Monitoring permission to the binary's code signature hash.
#    When /usr/local/bin/kanata-nix is replaced, the hash changes and permission is revoked.
#    Kanata then fails to create event taps and logs errors.
if [ "$RELOAD_REQUIRED" = false ]; then
    if [ -f /tmp/kanata.error.log ]; then
        if tail -100 /tmp/kanata.error.log 2>/dev/null | grep -qi "permission denied\|event.tap\|not permitted\|CGEventTap\|input monitoring\|accessibility\|failed to create\|cannot create" 2>/dev/null; then
            RELOAD_REQUIRED=true
            REASON="Input Monitoring permission may be lost (permission errors in log)"
        fi
    fi
fi

if [ "$RELOAD_REQUIRED" = true ]; then
    print_warning "Reloading Kanata: $REASON"

    # If the karabiner_grabber was denied TCC on IOHIDDeviceOpen, the DriverKit dext
    # still holds exclusive HID access. Force-restart the VirtualHIDDevice-Daemon to
    # kill the dext and release locked devices before restarting kanata.
    if [[ "$REASON" == *"IOHIDDeviceOpen"* ]] || [[ "$REASON" == *"HID devices may be locked"* ]]; then
        print_error "┌──────────────────────────────────────────────────────────────┐"
        print_error "│  karabiner_grabber lost Input Monitoring TCC permission.     │"
        print_error "│  The DriverKit dext holds HID devices exclusively, blocking  │"
        print_error "│  ALL keyboard input (even external keyboards).               │"
        print_error "│                                                              │"
        print_error "│  Force-restarting VirtualHIDDevice-Daemon to release HID...  │"
        print_error "└──────────────────────────────────────────────────────────────┘"
        osascript -e 'display notification "karabiner_grabber TCC denied — restarting VirtualHID daemon to unlock keyboards" with title "Keyboard Input Blocked" sound name "Glass"' 2>/dev/null || true
        print_status "Killing VirtualHIDDevice-Daemon and dext to release HID devices..."
        sudo /usr/bin/pkill -9 -f "Karabiner-VirtualHIDDevice-Daemon" 2>/dev/null || true
        sudo /usr/bin/pkill -9 -f "org.pqrs.Karabiner-DriverKit-VirtualHIDDevice" 2>/dev/null || true
        sleep 2
        print_status "Restarting VirtualHIDDevice-Daemon..."
        sudo /bin/launchctl kickstart -k system/org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon 2>/dev/null || true
        sleep 2
    fi

    # If Kanata specifically lost its Input Monitoring permission, notify user
    if [[ "$REASON" == *"Input Monitoring"* ]]; then
        print_error "┌──────────────────────────────────────────────────────────────┐"
        print_error "│  Kanata appears to have LOST Input Monitoring permission.    │"
        print_error "│                                                              │"
        print_error "│  Open: System Settings → Privacy & Security → Input Monitoring│"
        print_error "│  Re-grant permission to /usr/local/bin/kanata-nix            │"
        print_error "└──────────────────────────────────────────────────────────────┘"
        osascript -e 'display notification "Kanata lost Input Monitoring permission. Open System Settings → Privacy & Security → Input Monitoring → re-grant /usr/local/bin/kanata-nix" with title "Kanata Permission Lost" sound name "Glass"' 2>/dev/null || true
        open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent" 2>/dev/null || true
    fi

    # Ensure VirtualHIDDevice is healthy before restarting kanata.
    # After deep standby (hibernation), the virtual keyboard device can vanish from ioreg
    # even while the daemon process is still listed as running. Also, after killing the
    # daemon above (TCC deny case), we may need to wait for it to re-register.
    VIRTUALHID_OK=false
    for i in 1 2 3 4 5; do
        if ioreg -rn "Karabiner VirtualHIDKeyboard" >/dev/null 2>&1; then
            VIRTUALHID_OK=true
            break
        fi
        sleep 1
    done

    if [ "$VIRTUALHID_OK" = false ]; then
        print_warning "Karabiner VirtualHIDKeyboard not found in ioreg — attempting to restart VirtualHIDDevice-Daemon..."
        sudo /bin/launchctl kickstart -k system/org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon 2>/dev/null || true
        sleep 2
        print_status "VirtualHIDDevice-Daemon restarted."
    fi

    # 1b. Restart kanata - kickstart -k handles killing and starting
    # This is the fastest way to get the keyboard back.
    sudo /bin/launchctl kickstart -k system/local.kanata

    # 2. Parallel background cleanup of interfering processes
    # The grabber auto-respawns via Karabiner's internal XPC, so pkill alone is
    # insufficient. Make it non-executable as defense-in-depth so it cannot respawn.
    (
        KARABINER_BIN="/Library/Application Support/org.pqrs/Karabiner-Elements/bin"
        sudo chmod -x "$KARABINER_BIN/karabiner_grabber" 2>/dev/null || true
        sudo /bin/launchctl bootout system/org.pqrs.service.daemon.Karabiner-Core-Service 2>/dev/null || true
        sudo /bin/launchctl bootout system/org.pqrs.service.daemon.karabiner_grabber 2>/dev/null || true
        sudo /usr/bin/pkill -x "Karabiner-Core-Service" 2>/dev/null || true
        sudo /usr/bin/pkill -x "karabiner_grabber" 2>/dev/null || true
    ) >/dev/null 2>&1 &

    print_status "✓ Reload initiated (fast path)."
else
    print_status "✓ Kanata is healthy. Skipping reload."
fi
