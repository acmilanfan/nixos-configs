#!/bin/bash

# Get memory usage: from $MEM variable if triggered by system_info_update,
# or from memory_pressure as fallback.
if [ -n "$MEM" ]; then
  MEMORY=$MEM
else
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
fi

if [[ $MEMORY -ge 60 ]]; then
  COLOR="0xfff7768e"  # Critical red (high pressure)
elif [[ $MEMORY -ge 30 ]]; then
  COLOR="0xffe0af68"  # Warning yellow (medium pressure)
else
  COLOR="0xff9ece6a"  # Normal green (low pressure)
fi

MEMORY_DISPLAY=$(printf "%.0f" "$MEMORY")
sketchybar --set $NAME label="${MEMORY_DISPLAY}%" icon.color="$COLOR"
