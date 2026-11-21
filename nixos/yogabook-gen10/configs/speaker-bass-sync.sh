#!/usr/bin/env bash

# Keep the Yoga Book's Bass Speaker volume and switch in sync with the main
# Speaker control. PipeWire/WirePlumber only owns "Speaker Playback Volume";
# UCM only switches Bass on and off, so the bass level has to be mirrored here.
#
# Usage:
#   speaker-bass-sync --once   apply the current Speaker level to Bass and exit
#   speaker-bass-sync          apply once, then react to Speaker control events

set -uo pipefail

CARD="${SPEAKER_BASS_CARD:-sofhdadsp}"
VOLUME_CTL="Speaker Playback Volume"
SWITCH_CTL="Speaker Playback Switch"
BASS_VOLUME_CTL="Bass Speaker Playback Volume"
BASS_SWITCH_CTL="Bass Speaker Playback Switch"
# Bass is kept 6% below the main speaker (94% of its level), so it gets a
# little more weight at lower volumes than a fixed step offset would.
BASS_PERCENT=94

log() {
    printf '%s\n' "$*" >&2
}

control_exists() {
    amixer -c "$CARD" cget "name=$1" >/dev/null 2>&1
}

# Read the left-channel value: an integer for volumes, on/off for switches.
read_value() {
    amixer -c "$CARD" cget "name=$1" 2>/dev/null |
        awk -F'values=' '/^  : values=/{sub(/,.*/, "", $2); print $2; exit}'
}

sync_once() {
    control_exists "$VOLUME_CTL" || return 0

    local speaker bass_target bass_now speaker_switch bass_switch_now
    speaker=$(read_value "$VOLUME_CTL")
    [[ -n "$speaker" ]] || return 0

    bass_target=$(( (speaker * BASS_PERCENT + 50) / 100 ))
    bass_now=$(read_value "$BASS_VOLUME_CTL")
    if [[ -n "$bass_now" && "$bass_now" != "$bass_target" ]]; then
        if amixer -c "$CARD" cset "name=$BASS_VOLUME_CTL" \
            "${bass_target},${bass_target}" >/dev/null 2>&1; then
            log "bass volume ${bass_now} -> ${bass_target} (speaker ${speaker})"
        fi
    fi

    speaker_switch=$(read_value "$SWITCH_CTL")
    bass_switch_now=$(read_value "$BASS_SWITCH_CTL")
    if [[ -n "$speaker_switch" && -n "$bass_switch_now" &&
          "$bass_switch_now" != "$speaker_switch" ]]; then
        if amixer -c "$CARD" cset "name=$BASS_SWITCH_CTL" \
            "$speaker_switch" >/dev/null 2>&1; then
            log "bass switch ${bass_switch_now} -> ${speaker_switch}"
        fi
    fi
}

wait_for_card() {
    until control_exists "$VOLUME_CTL"; do
        sleep 1
    done
}

monitor_pid=""
fifo_dir=""

cleanup_monitor() {
    if [[ -n "$monitor_pid" ]]; then
        kill "$monitor_pid" 2>/dev/null
        wait "$monitor_pid" 2>/dev/null
        monitor_pid=""
    fi
    if [[ -n "$fifo_dir" ]]; then
        rm -rf "$fifo_dir"
        fifo_dir=""
    fi
}

watch() {
    trap 'cleanup_monitor; exit 0' INT TERM
    trap cleanup_monitor EXIT

    while true; do
        wait_for_card
        sync_once

        local card_index fifo
        card_index=$(awk '/\[sofhdadsp/{print $1; exit}' /proc/asound/cards 2>/dev/null)
        if [[ -z "$card_index" ]]; then
            sleep 1
            continue
        fi

        fifo_dir=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/speaker-bass-sync.XXXXXX") || {
            fifo_dir=""
            sleep 1
            continue
        }
        fifo="$fifo_dir/events"
        if ! mkfifo "$fifo"; then
            rm -rf "$fifo_dir"
            fifo_dir=""
            sleep 1
            continue
        fi

        # A FIFO plus a signal-reading loop lets the service stop cleanly and
        # restarts the monitor if the card goes away (suspend, USB reorder, ...).
        stdbuf -oL alsactl monitor "hw:${card_index}" >"$fifo" 2>/dev/null &
        monitor_pid=$!

        while IFS= read -r line; do
            case "$line" in
                *",Speaker Playback Volume,0)"* | *",Speaker Playback Switch,0)"*)
                    sync_once
                    ;;
            esac
        done <"$fifo"

        cleanup_monitor
        sleep 1
    done
}

case "${1:-}" in
    --once) sync_once ;;
    "") watch ;;
    *)
        echo "usage: $0 [--once]" >&2
        exit 2
        ;;
esac
