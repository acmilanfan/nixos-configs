#!/usr/bin/env bash
set -euo pipefail
script=$(dirname "$0")/../hypr-kanata-menu
export FIXTURE; FIXTURE=$(mktemp -d "$HOME/ai/artifacts/nixos-configs/quickshell-shell/kanata.XXXXXX" 2>/dev/null || mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
export HOME="$FIXTURE/home" PATH="$FIXTURE:$PATH"
mkdir -p "$HOME/.config/kanata"
cat > "$HOME/.config/kanata/switch-kanata.sh" <<'SH'
#!/usr/bin/env bash
printf 'switch %s\n' "$*" >> "$FIXTURE/calls"
SH
cat > "$HOME/.config/kanata/reload-kanata.sh" <<'SH'
#!/usr/bin/env bash
printf 'reload %s\n' "$*" >> "$FIXTURE/calls"
SH
cat > "$FIXTURE/vicinae" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$CHOICE"
SH
chmod +x "$HOME/.config/kanata"/*.sh "$FIXTURE/vicinae"
check() {
  rm -f "$FIXTURE/calls"
  CHOICE="$1" bash "$script"
  [[ $(cat "$FIXTURE/calls") == "$2" ]] || { echo "$1: got $(cat "$FIXTURE/calls")" >&2; exit 1; }
}
check 'Home Row' 'switch homerow'
check Disabled 'switch disabled'
check Reload 'reload restart'
rm -f "$FIXTURE/calls"; CHOICE='' bash "$script"; [[ ! -e "$FIXTURE/calls" ]]
echo 'hypr-kanata-menu: all cases passed'
