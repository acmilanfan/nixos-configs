#!/usr/bin/env bash
set -euo pipefail

helper=$(dirname "$0")/../hypr-focus-or-spawn
scratch="$HOME/ai/artifacts/nixos-configs/hammerspoon-parity"
mkdir -p "$scratch"
export FIXTURE
FIXTURE=$(mktemp -d "$scratch/spawn.XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT
export PATH="$FIXTURE:$PATH"

cat > "$FIXTURE/hyprctl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    '-j clients'|'clients -j') cat "$FIXTURE/clients.json" ;;
    '-j activeworkspace'|'activeworkspace -j') printf '{"id":7}\n' ;;
    dispatch\ *) shift; printf '%s\n' "$*" >> "$FIXTURE/dispatch" ;;
    *) exit 2 ;;
esac
EOF
chmod +x "$FIXTURE/hyprctl"

clients() { printf '%s\n' "$1" > "$FIXTURE/clients.json"; }
run() { rm -f "$FIXTURE/dispatch" "$FIXTURE/spawned"; bash "$helper" "$@"; }
dispatches() { cat "$FIXTURE/dispatch" 2>/dev/null || true; }
no_dispatch() {
    if [[ -e "$FIXTURE/dispatch" ]]; then
        echo "Unexpected dispatch: $(dispatches)" >&2
        exit 1
    fi
}
spawned_once() {
    for _ in $(seq 50); do [[ -e "$FIXTURE/spawned" ]] && break; sleep 0.02; done
    [[ $(grep -c . "$FIXTURE/spawned" 2>/dev/null || echo 0) == 1 ]] ||
        { echo "Expected exactly one spawn" >&2; exit 1; }
}

# A match focuses the exact address and reuses the window in order.
clients '[{"class":"orgindex","title":"ORGINDEX-AGENDA","address":"0xabc","mapped":true}]'
run orgindex AGENDA true
[[ $(dispatches) == $'hl.dsp.focus({window = \'address:0xabc\'})\nhl.dsp.window.move({workspace = \'7\'})\nhl.dsp.window.float()\nhl.dsp.window.center()' ]]
[[ ! -e "$FIXTURE/spawned" ]]

# Titles are matched case-insensitively even with quotes, tabs, and newlines.
clients '[{"class":"orgindex","title":"he said \"AGENDA\"\tnow\nAGENDA","address":"0xdef","mapped":true}]'
run orgindex agenda true
[[ $(head -n 1 "$FIXTURE/dispatch") == "hl.dsp.focus({window = 'address:0xdef'})" ]]
[[ $(grep -c . "$FIXTURE/dispatch") == 4 ]]

# A different class, no clients, or an unmapped match spawns instead.
clients '[{"class":"yazi","title":"ORGINDEX-AGENDA","address":"0xbad","mapped":true}]'
run orgindex AGENDA 'echo x >>' "$FIXTURE/spawned"
spawned_once
no_dispatch

clients '[]'
run orgindex AGENDA 'echo x >>' "$FIXTURE/spawned"
spawned_once
no_dispatch

clients '[{"class":"orgindex","title":"ORGINDEX-AGENDA","address":"0xbad","mapped":false}]'
run orgindex AGENDA 'echo x >>' "$FIXTURE/spawned"
spawned_once
no_dispatch

echo 'hypr-focus-or-spawn: all cases passed'
