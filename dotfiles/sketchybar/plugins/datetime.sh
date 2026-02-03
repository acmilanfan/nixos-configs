#!/bin/bash

# Format: "Mon 14:30"
DAY=$(date '+%a')
TIME=$(date '+%H:%M')
sketchybar --set $NAME label="$DAY $TIME"
