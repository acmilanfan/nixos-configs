#!/usr/bin/env bash
set -euo pipefail

helper=$(dirname "$0")/../hypr-window-adapt
scratch="$HOME/ai/artifacts/nixos-configs/hammerspoon-parity"
mkdir -p "$scratch"
export FIXTURE
FIXTURE=$(mktemp -d "$scratch/adapt.XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT
export PATH="$FIXTURE:$PATH"

cat > "$FIXTURE/hyprctl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    '-j activewindow'|'activewindow -j') cat "$FIXTURE/window.json" ;;
    dispatch\ *) shift; printf '%s\n' "$*" >> "$FIXTURE/dispatch" ;;
    *) exit 2 ;;
esac
EOF
chmod +x "$FIXTURE/hyprctl"

window() { printf '%s\n' "$1" > "$FIXTURE/window.json"; }
check() {
    local floating=$1 action=$2 expected=$3
    window "{\"floating\":$floating}"
    rm -f "$FIXTURE/dispatch"
    bash "$helper" "$action"
    [[ $(cat "$FIXTURE/dispatch") == "$expected" ]] ||
        { echo "$floating/$action: got $(cat "$FIXTURE/dispatch")" >&2; exit 1; }
}

check true h 'resizeactive -40 0'
check true l 'resizeactive 40 0'
check true k 'resizeactive 0 -40'
check true j 'resizeactive 0 40'
check false h 'hl.dsp.window.swap({prev = true})'
check false l 'hl.dsp.window.swap({next = true})'
check false k 'hl.dsp.window.swap({prev = true})'
check false j 'hl.dsp.window.swap({next = true})'
check null j 'hl.dsp.window.swap({next = true})'

window '{"floating":true}'
rm -f "$FIXTURE/dispatch"
if bash "$helper" x 2>/dev/null; then
    echo "Unknown action should fail" >&2
    exit 1
fi
[[ ! -e "$FIXTURE/dispatch" ]] || { echo 'Unknown action dispatched' >&2; exit 1; }

echo 'hypr-window-adapt: all cases passed'
