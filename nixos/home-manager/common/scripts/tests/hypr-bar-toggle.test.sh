#!/usr/bin/env bash
set -euo pipefail
script=$(dirname "$0")/../hypr-bar-toggle
export FIXTURE; FIXTURE=$(mktemp -d "$HOME/ai/artifacts/nixos-configs/quickshell-shell/bars.XXXXXX" 2>/dev/null || mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
export PATH="$FIXTURE:$PATH"
cat > "$FIXTURE/hypr-quickshell-shell" <<'SH'
#!/usr/bin/env bash
printf 'qs %s\n' "$*" >> "$FIXTURE/calls"
SH
cat > "$FIXTURE/hypr-waybar-toggle" <<'SH'
#!/usr/bin/env bash
printf 'waybar %s\n' "$*" >> "$FIXTURE/calls"
SH
cat > "$FIXTURE/pkill" <<'SH'
#!/usr/bin/env bash
printf 'pkill %s\n' "$*" >> "$FIXTURE/calls"
SH
chmod +x "$FIXTURE"/*
bash "$script" top
grep -qx 'qs bars top' "$FIXTURE/calls"
mkdir -p "$FIXTURE/nobin"
ln -s "$FIXTURE/pkill" "$FIXTURE/nobin/pkill"
ln -s "$FIXTURE/hypr-waybar-toggle" "$FIXTURE/nobin/hypr-waybar-toggle"
ln -s "$(command -v bash)" "$FIXTURE/nobin/bash"
rm -f "$FIXTURE/calls"
PATH="$FIXTURE/nobin:/run/current-system/sw/bin" bash "$script" top
grep -qx 'pkill -USR1 -f waybar.*top' "$FIXTURE/calls"
rm -f "$FIXTURE/calls"
PATH="$FIXTURE/nobin:/run/current-system/sw/bin" bash "$script" all
grep -qx 'waybar ' "$FIXTURE/calls"
echo 'hypr-bar-toggle: all cases passed'
