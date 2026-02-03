#!/bin/bash

# Use system_profiler to get WiFi signal strength (works on all macOS versions)
SIGNAL_INFO=$(system_profiler SPAirPortDataType 2>/dev/null | grep "Signal / Noise" | head -1)

if [ -n "$SIGNAL_INFO" ]; then
  # Extract signal strength (e.g., "-55 dBm")
  RSSI=$(echo "$SIGNAL_INFO" | sed 's/.*: /' | cut -d' ' -f1)

  if [ -n "$RSSI" ] && [ "$RSSI" -lt 0 ] 2>/dev/null; then
    # WiFi is connected - show signal strength icon and value
    if [[ $RSSI -ge -50 ]]; then
      ICON="󰤨"  # Excellent (4 bars)
      COLOR="0xff9ece6a"
    elif [[ $RSSI -ge -60 ]]; then
      ICON="󰤥"  # Good (3 bars)
      COLOR="0xff7aa2f7"
    elif [[ $RSSI -ge -70 ]]; then
      ICON="󰤢"  # Fair (2 bars)
      COLOR="0xffe0af68"
    else
      ICON="󰤟"  # Weak (1 bar)
      COLOR="0xfff7768e"
    fi
    sketchybar --set $NAME icon="$ICON" icon.color="$COLOR" label=""
    exit 0
  fi
fi

# Fallback: Check if connected via scutil
NETWORK_STATUS=$(scutil --nwi 2>/dev/null | grep "IPv4 network interface" -A1 | grep "en0")
if [ -n "$NETWORK_STATUS" ]; then
  # Connected but could not get signal strength
  sketchybar --set $NAME icon="󰤨" icon.color="0xff9ece6a" label=""
  exit 0
fi

# Check for ethernet on various interfaces
for iface in en1 en2 en3 en4 en5 en6; do
  ETHERNET=$(ifconfig $iface 2>/dev/null | grep "status: active")
  if [ -n "$ETHERNET" ]; then
    sketchybar --set $NAME icon="󰈀" icon.color="0xff9ece6a" label=""
    exit 0
  fi
done

# Check if WiFi is on but not connected
WIFI_POWER=$(networksetup -getairportpower en0 2>/dev/null | grep "On")
if [ -n "$WIFI_POWER" ]; then
  sketchybar --set $NAME icon="󰤯" icon.color="0xff565f89" label=""
else
  sketchybar --set $NAME icon="󰤭" icon.color="0xff565f89" label=""
fi
