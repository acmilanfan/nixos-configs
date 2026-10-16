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

# stderr apart from the code: a gpg warning must never be copied with it.
err="$(mktemp)"
trap 'rm -f "$err"' EXIT
code="$(pass otp "$choice" 2>"$err")" || {
  head -3 "$err"
  exit 1
}

# Same handling as the nanowm pass module: mark the entry concealed so
# clipboard managers (Vicinae, Maccy) don't keep it in history, and clear it
# after 45s unless something else was copied meanwhile.
OTP_CODE="$code" osascript -l JavaScript >/dev/null <<'JS'
ObjC.import("AppKit");
const code = $.NSProcessInfo.processInfo.environment.objectForKey("OTP_CODE");
const pb = $.NSPasteboard.generalPasteboard;
pb.clearContents;
pb.setStringForType(code, $.NSPasteboardTypeString);
pb.setStringForType($(""), $("org.nspasteboard.ConcealedType"));
JS
OTP_CODE="$code" nohup /bin/sh -c \
  'sleep 45; [ "$(pbpaste)" = "$OTP_CODE" ] && printf "" | pbcopy' \
  >/dev/null 2>&1 &
echo "OTP code copied to clipboard (cleared in 45s)"
