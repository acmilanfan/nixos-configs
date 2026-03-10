#!/usr/bin/env bash

# This script synchronizes 'Bass Speaker' with 'Speaker' volume
# with a -6% offset for the Bass Speaker.
# It retries to ensure pipewire/alsa are ready.

LOG_FILE="/tmp/sync-volume.log"
echo "Starting sync-volume at $(date)" > "$LOG_FILE"

# Wait a bit for the system to settle
sleep 2

for i in {1..15}; do
    # Try to get volume from pamixer (Pipewire)
    SPEAKER_VOL=$(pamixer --get-volume 2>/dev/null)

    if [ -n "$SPEAKER_VOL" ]; then
        # Calculate Bass volume (Speaker - 6)
        BASS_VOL=$(( SPEAKER_VOL - 6 ))
        if [ "$BASS_VOL" -lt 0 ]; then BASS_VOL=0; fi

        echo "Found volume: $SPEAKER_VOL. Setting Bass to $BASS_VOL." >> "$LOG_FILE"

        # Apply to hardware controls
        # We do NOT touch Master as requested
        amixer -c sofhdadsp sset 'Speaker' "${SPEAKER_VOL}%" >> "$LOG_FILE" 2>&1
        amixer -c sofhdadsp sset 'Bass Speaker' "${BASS_VOL}%" >> "$LOG_FILE" 2>&1

        echo "Sync complete." >> "$LOG_FILE"
        exit 0
    fi
    echo "Waiting for audio system... (attempt $i)" >> "$LOG_FILE"
    sleep 1
done
echo "Failed to sync volume after 15 attempts" >> "$LOG_FILE"
