#!/bin/bash
# The CI account only writes records. This helper always runs as the desktop user.
[ -f "$HOME/.config/local-ci-status/enabled" ] || exit 0
command -v local-ci-status >/dev/null 2>&1 || exit 0
case "${SENDER:-}" in
  mouse.clicked) local-ci-status popup ;;
  mouse.exited.global) sketchybar --set ci_status popup.drawing=off ;;
  *) local-ci-status refresh ;;
esac
exit 0
