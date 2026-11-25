# Root helper for kanata/Karabiner operations, installed as kanata-ctl by
# darwin/common.nix. sudoers allows only this path, so keep every root action
# behind a fixed subcommand and never honor environment-provided command paths.
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
KARABINER_BIN="/Library/Application Support/org.pqrs/Karabiner-Elements/bin"
VHID=system/org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon
KANATA_LABEL=system/local.kanata
KANATA_PLIST=/Library/LaunchDaemons/local.kanata.plist
KANATA_PROC=kanata-nix

# karabiner_grabber/Karabiner-Core-Service open HID keyboards exclusively;
# without Input Monitoring TCC that blocks ALL keyboard input. They respawn
# via Karabiner's XPC, so killing them isn't enough: make them unexecutable.
neutralize() {
    for b in karabiner_grabber karabiner_console_user_server karabiner_session_monitor; do
        [ -e "$KARABINER_BIN/$b" ] && chmod -x "$KARABINER_BIN/$b"
    done
    launchctl bootout system/org.pqrs.service.daemon.Karabiner-Core-Service 2>/dev/null
    launchctl bootout system/org.pqrs.service.daemon.karabiner_grabber 2>/dev/null
    pkill -9 -x Karabiner-Core-Service 2>/dev/null
    pkill -9 -f karabiner_grabber 2>/dev/null
    pkill -9 -f karabiner_console_user_server 2>/dev/null
    true
}

# Kill the VirtualHID daemon and its dext (releases a stale exclusive HID
# lock), then start it again so kanata has a virtual keyboard to emit to.
reset_hid() {
    pkill -9 -f Karabiner-VirtualHIDDevice-Daemon 2>/dev/null
    pkill -9 -f org.pqrs.Karabiner-DriverKit-VirtualHIDDevice 2>/dev/null
    sleep 2
    launchctl kickstart -k "$VHID" 2>/dev/null
    true
}

# ioreg exits 0 even when -n matches nothing, so its exit status cannot test
# for a device. hidutil lists the HID services actually present.
virtual_hid_present() {
    hidutil list 2>/dev/null | grep -qi 'Karabiner.*VirtualHIDKeyboard'
}

# Print "restarted" only when the daemon was actually restarted, so callers
# can wait for the virtual keyboard to re-register.
ensure_hid() {
    if virtual_hid_present; then
        return 0
    fi
    launchctl kickstart -k "$VHID" 2>/dev/null || true
    echo restarted
}

# True when the kanata process still owns a live IOHIDLibUserClient on the
# keyboard. The enumeration client (IOHIDParamUserClient) is not enough: on a
# DarkWake the input grab can silently vanish while the output sink stays
# healthy (upstream #2094).
input_grab_present() {
    local pid=$1
    LC_ALL=C ioreg -c IOHIDLibUserClient -l -w0 2>/dev/null \
        | LC_ALL=C awk -v pid="$pid" '
            /^ *[|+ ]*\+-o IOHIDLibUserClient  <class/ { inlib = 1; creator = 0; opened = 0; next }
            /^ *[|+ ]*\+-o / { inlib = 0 }
            inlib && /"IOUserClientCreator" = "pid / { if (index($0, "pid " pid ", kanata-nix")) creator = 1 }
            inlib && /"ClientOpened"[[:space:]]*=[[:space:]]*Yes/ { opened = 1 }
            inlib && creator && opened { found = 1 }
            END { exit found ? 0 : 1 }
        '
}

# Verify the process not only exists but still delivers input. Native
# recovery releases the grab for a few seconds after a sink loss, so wait
# before declaring failure; the caller then restarts kanata.
health() {
    local i=0 pid
    while [ "$i" -lt 10 ]; do
        pid=$(pgrep -x kanata-nix | head -1)
        if [ -n "$pid" ] && input_grab_present "$pid"; then
            return 0
        fi
        sleep 0.5
        i=$((i + 1))
    done
    echo "kanata-ctl: kanata input grab not present" >&2
    return 1
}

# Unload the daemon and wait for the old process to exit. launchctl kickstart -k
# starts the replacement immediately, before the old instance releases the
# seized keyboard; that race left kanata running but deaf (2026-11-25).
stop_kanata() {
    launchctl bootout "$KANATA_LABEL" 2>/dev/null || true
    local i=0
    while pgrep -x "$KANATA_PROC" >/dev/null 2>&1 && [ "$i" -lt 50 ]; do
        sleep 0.1
        i=$((i + 1))
    done
    if pgrep -x "$KANATA_PROC" >/dev/null 2>&1; then
        pkill -9 -x "$KANATA_PROC" 2>/dev/null || true
        sleep 1
    fi
}

start_kanata() {
    launchctl bootstrap system "$KANATA_PLIST" 2>/dev/null || true
    local i=0
    while ! pgrep -x "$KANATA_PROC" >/dev/null 2>&1 && [ "$i" -lt 50 ]; do
        sleep 0.1
        i=$((i + 1))
    done
    pgrep -x "$KANATA_PROC" >/dev/null 2>&1
}

restart_kanata() {
    stop_kanata
    # Let the kernel/driver finish releasing the seized keyboard before the
    # replacement opens it.
    sleep 1
    if start_kanata; then
        return 0
    fi
    sleep 1
    start_kanata && return 0
    echo "kanata-ctl: failed to start local.kanata" >&2
    return 1
}

main() {
    case "${1:-}" in
        neutralize) neutralize ;;
        reset-hid) reset_hid ;;
        ensure-hid) ensure_hid ;;
        health) health ;;
        restart) restart_kanata ;;
        # Emergency: SIGKILL first so a hung kanata lets go of the keyboard at
        # once, then the ordered restart. Leaving the respawn to KeepAlive
        # races the release of the seized keyboard (see stop_kanata).
        kill)
            pkill -9 -x "$KANATA_PROC" 2>/dev/null
            restart_kanata
            ;;
        rescue)
            neutralize
            stop_kanata
            reset_hid
            sleep 1
            start_kanata || {
                echo "kanata-ctl: failed to start local.kanata after rescue" >&2
                return 1
            }
            ;;
        tcc-denied)
            log show --last 5m --style compact \
                --predicate 'eventMessage CONTAINS "TCC deny IOHIDDeviceOpen" AND process == "karabiner_grabber"' \
                2>/dev/null | grep -q "TCC deny"
            ;;
        *)
            echo "usage: kanata-ctl neutralize|reset-hid|ensure-hid|health|restart|kill|rescue|tcc-denied" >&2
            exit 2
            ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
