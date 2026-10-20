#!/usr/bin/env bash
# Hardware (DPCD) backlight control for both Yoga Book panels.
# Usage: brightness-ctl {set PCT | up [STEP] | down [STEP]}
# The eDP-2 backlight is named cardN-eDP-2-backlight, where N can change
# between boots, so match it with a wildcard instead of a fixed card number.

exec 9>"${XDG_RUNTIME_DIR:-$HOME/.cache}/brightness-ctl.lock"
flock -w 3 9 || exit 0

set_both() {
  brightnessctl -d '*-eDP-2-backlight' s "$1" 2>/dev/null || true
  brightnessctl -d 'intel_backlight' s "$1" 2>/dev/null || true
}

case "$1" in
  set)
    [ -z "$2" ] && exit 1
    pct="${2%\%}"
    set_both "${pct}%"
    ;;
  up)
    STEP="${2:-5}"
    set_both "+${STEP}%"
    ;;
  down)
    STEP="${2:-5}"
    set_both "${STEP}%-"
    ;;
  *)
    echo "Usage: brightness-ctl {set PCT | up [STEP] | down [STEP]}"
    exit 1
    ;;
esac
