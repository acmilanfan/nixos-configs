#!/bin/bash

# Memory plugin matching AwesomeWM's ram widget

source "$CONFIG_DIR/colors.sh"

MEMORY_PRESSURE=$(memory_pressure | grep "System-wide memory free percentage:" | awk '{print 100-$5}' | sed 's/%//')
if [ -z "$MEMORY_PRESSURE" ]; then
  MEMORY_PRESSURE=$(vm_stat | awk '/Pages free/ {free=$3} /Pages active/ {active=$3} /Pages inactive/ {inactive=$3} /Pages speculative/ {spec=$3} /Pages wired/ {wired=$3} END {total=free+active+inactive+spec+wired; used=active+inactive+wired; printf "%.0f", used/total*100}')
fi

sketchybar --set $NAME icon="$MEMORY" label="$MEMORY_PRESSURE%"

