#!/bin/bash

# Get memory pressure (percentage of memory used)
MEMORY=$(memory_pressure 2>/dev/null | grep "System-wide memory free percentage" | awk '{print 100 - $5}' | tr -d '%')

# Fallback if memory_pressure doesn't work
if [ -z "$MEMORY" ]; then
  # Use vm_stat as fallback
  PAGES_FREE=$(vm_stat | grep "Pages free" | awk '{print $3}' | tr -d '.')
  PAGES_ACTIVE=$(vm_stat | grep "Pages active" | awk '{print $3}' | tr -d '.')
  PAGES_INACTIVE=$(vm_stat | grep "Pages inactive" | awk '{print $3}' | tr -d '.')
  PAGES_WIRED=$(vm_stat | grep "Pages wired" | awk '{print $4}' | tr -d '.')
  PAGES_COMPRESSED=$(vm_stat | grep "Pages occupied by compressor" | awk '{print $5}' | tr -d '.')

  TOTAL=$((PAGES_FREE + PAGES_ACTIVE + PAGES_INACTIVE + PAGES_WIRED + PAGES_COMPRESSED))
  USED=$((PAGES_ACTIVE + PAGES_WIRED + PAGES_COMPRESSED))

  if [ $TOTAL -gt 0 ]; then
    MEMORY=$((USED * 100 / TOTAL))
  else
    MEMORY=0
  fi
fi

if [[ $MEMORY -ge 80 ]]; then
  COLOR="0xfff7768e"  # Critical red
elif [[ $MEMORY -ge 60 ]]; then
  COLOR="0xffe0af68"  # Warning yellow
else
  COLOR="0xff9ece6a"  # Normal green
fi

sketchybar --set $NAME label="$MEMORY%" icon.color="$COLOR"
