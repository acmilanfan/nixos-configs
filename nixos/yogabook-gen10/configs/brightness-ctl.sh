#!/usr/bin/env bash
# Brightness control via hyprsunset gamma (Hyprland-native CTM protocol).
# Usage: brightness-ctl {set PCT | up [STEP%] | down [STEP%] | restore}

exec 9>/tmp/brightness-ctl.lock
flock -w 3 9 || exit 0

get_pct() {
  _c=$(brightnessctl g 2>/dev/null)
  _m=$(brightnessctl m 2>/dev/null)
  [ -n "$_c" ] && [ -n "$_m" ] && [ "$_m" -gt 0 ] \
    && awk -v c="$_c" -v m="$_m" 'BEGIN {printf "%.3f", c/m}'
}

apply() {
  local p="$1"
  [ -z "$p" ] && return
  local gamma=$(awk -v p="$p" 'BEGIN {printf "%.0f", p*100}')
  H=$(date +%k | tr -d ' ')
  local temp=6000; [ "$H" -ge 21 ] || [ "$H" -lt 6 ] && temp=3500
  pkill -9 hyprsunset 2>/dev/null
  while pgrep hyprsunset >/dev/null 2>&1; do :; done
  exec 9>&-  # release flock so child doesn't inherit it
  hyprsunset -g "$gamma" -t "$temp" &>/dev/null &
}

case "$1" in
  set)
    apply "$2"
    ;;
  up)
    STEP="${2:-5}"
    brightnessctl s "+${STEP}%"
    brightnessctl --device='intel_backlight' s "+${STEP}%"
    apply "$(get_pct)"
    ;;
  down)
    STEP="${2:-5}"
    brightnessctl s "${STEP}%-"
    brightnessctl --device='intel_backlight' s "${STEP}%-"
    apply "$(get_pct)"
    ;;
  restore)
    apply "$(get_pct)"
    ;;
  *)
    echo "Usage: brightness-ctl {set PCT | up [STEP%] | down [STEP%] | restore}"
    exit 1
    ;;
esac
