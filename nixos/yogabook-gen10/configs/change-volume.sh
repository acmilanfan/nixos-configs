#!/usr/bin/env bash

# This script changes both 'Speaker' and 'Bass Speaker' volume by a step
# Card 1 is the sof-hda-dsp card on the Yoga Book Gen 10

STEP=${1:-5} # Default to 5% step

# Use amixer to change both controls at once
# We use Speaker as the primary reference

if [[ "$STEP" == +* ]]; then
    amixer -c 1 sset 'Speaker' "${STEP#+}%+" > /dev/null
    amixer -c 1 sset 'Bass Speaker' "${STEP#+}%+" > /dev/null
elif [[ "$STEP" == -* ]]; then
    amixer -c 1 sset 'Speaker' "${STEP#-}%-" > /dev/null
    amixer -c 1 sset 'Bass Speaker' "${STEP#-}%-" > /dev/null
else
    # Treat as absolute if no +/-
    amixer -c 1 sset 'Speaker' "${STEP}%" > /dev/null
    amixer -c 1 sset 'Bass Speaker' "${STEP}%" > /dev/null
fi
