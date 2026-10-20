#!/usr/bin/env bash
# Legacy wrapper around brightness-ctl: +5% / 5%- or a bare step.
case "$1" in
  +*)
    STEP="${1#+}"
    exec brightness-ctl up "${STEP%\%}"
    ;;
  -*)
    STEP="${1%-}"
    exec brightness-ctl down "${STEP%\%}"
    ;;
  *)
    exec brightness-ctl up "${1:-5}"
    ;;
esac
