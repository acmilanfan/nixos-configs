#!/usr/bin/env bash
set -euo pipefail

script=$(dirname "$0")/../hypr-commands
scratch="$HOME/ai/artifacts/nixos-configs/hyprland-mac-keybinds"
mkdir -p "$scratch"
export FIXTURE
FIXTURE=$(mktemp -d "$scratch/commands.XXXXXX")
trap 'rm -f "$FIXTURE/"{hyprctl,vicinae,hypr-quickshell-pilot,rows,dispatch}; rmdir "$FIXTURE"' EXIT
export PATH="$FIXTURE:$PATH"

cat > "$FIXTURE/vicinae" <<'EOF'
#!/usr/bin/env bash
cat > "$FIXTURE/rows"
printf '%s\n' "$CHOICE"
EOF
cat > "$FIXTURE/hyprctl" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == dispatch ]] || exit 2
printf '%s\n' "$2" >> "$FIXTURE/dispatch"
EOF
cat > "$FIXTURE/hypr-quickshell-pilot" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FIXTURE/dispatch"
EOF
chmod +x "$FIXTURE/"{hyprctl,vicinae,hypr-quickshell-pilot}

check() {
    local choice=$1 expected=$2
    : > "$FIXTURE/dispatch"
    CHOICE="$choice" bash "$script"
    [[ $(cat "$FIXTURE/dispatch") == "$expected" ]] ||
        { echo "Unexpected dispatcher for '$choice': $(cat "$FIXTURE/dispatch")" >&2; exit 1; }
    if [[ -n "$expected" ]]; then
        grep -Fxq "$choice" "$FIXTURE/rows"
    fi
}
check 'Toggle Pseudo-Tile' 'hl.dsp.window.pseudo()'
check 'Previous Master Orientation' 'hl.dsp.layout("orientationprev")'
check 'Quickshell pilot: Toggle' 'toggle'
check 'Not a command' ''
check '' ''
echo 'hypr-commands: all cases passed'
