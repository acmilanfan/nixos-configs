#!/bin/bash

# @vicinae.schemaVersion 1
# @vicinae.title Pass OTP
# @vicinae.mode compact
# @vicinae.packageName Pass
# @vicinae.icon 🔐
# @vicinae.description Pick a pass entry and copy its current OTP code to the clipboard (pass otp).

set -euo pipefail

# Same store resolution as the nanowm Hammerspoon module: PASSWORD_STORE_DIR
# wins, otherwise the default ~/.password-store (a symlink to the repo
# secrets on this machine).
STORE="${PASSWORD_STORE_DIR:-$HOME/.password-store}"

if [ ! -d "$STORE" ]; then
  echo "Password store not found at $STORE"
  exit 1
fi

# `pass otp ls` is not a valid subcommand in the current pass-otp; enumerate
# the store directly like the Hammerspoon menu does.
entries="$(find -L "$STORE" -name '*.gpg' -type f 2>/dev/null |
  sed -e "s|^$STORE/||" -e 's|\.gpg$||' | sort)"

if [ -z "$entries" ]; then
  echo "No entries in $STORE"
  exit 1
fi

choice="$(printf '%s\n' "$entries" | vicinae dmenu -W 500 -H 500 -p "OTP entry: ")" || exit 0
[ -n "$choice" ] || exit 0

code="$(pass otp "$choice" 2>&1)" || {
  echo "$code" | head -3
  exit 1
}

printf '%s' "$code" | pbcopy
echo "OTP code copied to clipboard"
