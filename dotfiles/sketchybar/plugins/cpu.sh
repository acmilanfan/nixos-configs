#!/bin/bash

# CPU plugin matching AwesomeWM's cpu widget

source "$CONFIG_DIR/colors.sh"

CPU_INFO=$(ps -eo pcpu | awk '{sum += $1} END {print sum}')
CPU_PERCENT=$(echo "$CPU_INFO" | awk '{printf "%.0f", $1}')

sketchybar --set $NAME icon="$CPU" label="$CPU_PERCENT%"

