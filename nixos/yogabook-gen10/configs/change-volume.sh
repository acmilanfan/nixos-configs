#!/usr/bin/env bash

# Change the main Speaker volume. The Bass Speaker is mirrored by
# speaker-bass-sync so both controls stay in step however the volume changes.
# Card is the sof-hda-dsp card on the Yoga Book Gen 10.

STEP=${1:-5} # Default to 5% step

if [[ "$STEP" == +* ]]; then
    amixer -c sofhdadsp sset 'Speaker' "${STEP#+}%+" > /dev/null
elif [[ "$STEP" == -* ]]; then
    amixer -c sofhdadsp sset 'Speaker' "${STEP#-}%-" > /dev/null
else
    # Treat as absolute if no +/-
    amixer -c sofhdadsp sset 'Speaker' "${STEP}%" > /dev/null
fi
