#!/usr/bin/env bash
set -euo pipefail
script=$(dirname "$0")/../hypr-layout-icon
export FIXTURE; FIXTURE=$(mktemp -d "$HOME/ai/artifacts/nixos-configs/quickshell-shell/layout.XXXXXX" 2>/dev/null || mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
export PATH="$FIXTURE:$PATH"
cat > "$FIXTURE/hyprctl" <<'SH'
#!/usr/bin/env bash
case "$*" in
  '-j activewindow') printf '{"fullscreen":%s}\n' "$(cat "$FIXTURE/full")" ;;
  '-j activeworkspace') printf '{"layout":"%s"}\n' "$(cat "$FIXTURE/layout")" ;;
  *) exit 2 ;;
esac
SH
chmod +x "$FIXTURE/hyprctl"
check() {
  printf '%s\n' "$1" > "$FIXTURE/full"; printf '%s\n' "$2" > "$FIXTURE/layout"
  [[ $(bash "$script") == "$3" ]] || { echo "$1/$2: got $(bash "$script")" >&2; exit 1; }
}
check 0 master '󰕮'
check 0 dwindle '󰘸'
check 0 scrolling '󰒋'
check 1 master '󰊓'
check 2 dwindle '󰊓'
echo 'hypr-layout-icon: all cases passed'
