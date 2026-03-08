#!/usr/bin/env bash

# This script synchronizes 'Bass Speaker' volume with 'Speaker' volume
# Card 1 is the sof-hda-dsp card on the Yoga Book Gen 10

# Get current Speaker volume (percentage)
SPEAKER_VOL=$(amixer -c 1 sget Speaker | grep -Po '\[\d+%\]' | head -1 | tr -d '[]%')

if [ -n "$SPEAKER_VOL" ]; then
    # Set Bass Speaker volume to match
    amixer -c 1 sset 'Bass Speaker' "${SPEAKER_VOL}%" > /dev/null

    # Also sync Master if it's lagging (optional, but Master usually controls both)
    # amixer -c 1 sset 'Master' "${SPEAKER_VOL}%" > /dev/null
fi
