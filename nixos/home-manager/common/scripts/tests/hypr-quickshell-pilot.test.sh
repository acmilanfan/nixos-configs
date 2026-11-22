#!/usr/bin/env bash
set -euo pipefail

helper=$(dirname "$0")/../hypr-quickshell-pilot
scratch="$HOME/ai/artifacts/nixos-configs/quickshell-pilot"
mkdir -p "$scratch"
export FIXTURE
FIXTURE=$(mktemp -d "$scratch/helper.XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT
export HOME="$FIXTURE/home"
mkdir -p "$HOME/.config/quickshell/pilot"
touch "$HOME/.config/quickshell/pilot/shell.qml"
export PATH="$FIXTURE:$PATH"
export WAYLAND_DISPLAY=wayland-test

cat > "$FIXTURE/pgrep" <<'EOF'
#!/usr/bin/env bash
case "$2" in
    *quickshell*) [[ -e "$FIXTURE/qs.running" ]] ;;
    *config-hypr-bottom*) [[ -e "$FIXTURE/waybar.running" ]] ;;
    *) exit 1 ;;
esac
EOF
cat > "$FIXTURE/pkill" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FIXTURE/pkill.log"
case "$2" in
    *quickshell*) rm -f "$FIXTURE/qs.running" ;;
    *config-hypr-bottom*) rm -f "$FIXTURE/waybar.running" ;;
    *) exit 1 ;;
esac
EOF
cat > "$FIXTURE/yb-mode" <<'EOF'
#!/usr/bin/env bash
printf 'signal=detached mode=%s override=auto\n' "$(cat "$FIXTURE/mode" 2>/dev/null || echo dual)"
EOF
cat > "$FIXTURE/setsid" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
cat > "$FIXTURE/quickshell" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FIXTURE/quickshell.log"
touch "$FIXTURE/qs.running"
EOF
cat > "$FIXTURE/waybar" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FIXTURE/waybar.log"
touch "$FIXTURE/waybar.running"
EOF
chmod +x "$FIXTURE"/{pgrep,pkill,yb-mode,setsid,quickshell,waybar}

printf 'dual\n' > "$FIXTURE/mode"
reset() {
    rm -f "$FIXTURE"/*.running "$FIXTURE"/*.log
}
run() { bash "$helper" "$@"; }
wait_for() {
    for _ in $(seq 100); do [[ -e "$1" ]] && return 0; sleep 0.02; done
    echo "Timed out waiting for $1" >&2
    exit 1
}

reset
run status | grep -qx 'quickshell pilot: stopped'

# Start stops the running bottom Waybar and leaves other instances alone.
touch "$FIXTURE/waybar.running" "$FIXTURE/top.running" "$FIXTURE/external.running"
run start
wait_for "$FIXTURE/quickshell.log"
grep -qx -- '-c pilot' "$FIXTURE/quickshell.log"
[[ ! -e "$FIXTURE/waybar.running" ]]
[[ -e "$FIXTURE/top.running" && -e "$FIXTURE/external.running" ]]

# Starting again does not launch a second bar.
run start
[[ $(grep -c . "$FIXTURE/quickshell.log") == 1 ]]

# Stop restores exactly one bottom Waybar; a second stop is a no-op.
run stop
wait_for "$FIXTURE/waybar.log"
[[ ! -e "$FIXTURE/qs.running" ]]
grep -q -- '-c .*config-hypr-bottom' "$FIXTURE/waybar.log"
grep -q -- '-s .*style-hypr.css' "$FIXTURE/waybar.log"
run stop
[[ $(grep -c . "$FIXTURE/waybar.log") == 1 ]]

# Toggle both directions.
reset
run toggle
wait_for "$FIXTURE/qs.running"
run toggle
wait_for "$FIXTURE/waybar.running"
[[ ! -e "$FIXTURE/qs.running" ]]

# Laptop mode: start refuses, stop does not resurrect the hidden Waybar.
reset
printf 'laptop\n' > "$FIXTURE/mode"
if run start 2>/dev/null; then
    echo "Start must refuse in laptop mode" >&2
    exit 1
fi
[[ ! -e "$FIXTURE/qs.running" && ! -e "$FIXTURE/waybar.running" && ! -e "$FIXTURE/quickshell.log" ]]
touch "$FIXTURE/qs.running"
run stop
[[ ! -e "$FIXTURE/waybar.running" && ! -e "$FIXTURE/waybar.log" ]]

# Missing Quickshell, missing config, or no Wayland session must not hide Waybar.
reset
printf 'dual\n' > "$FIXTURE/mode"
mkdir -p "$FIXTURE/nobin"
for cmd in pgrep pkill yb-mode setsid waybar; do ln -s "$FIXTURE/$cmd" "$FIXTURE/nobin/$cmd"; done
if PATH="$FIXTURE/nobin:/usr/bin:/bin" run start 2>/dev/null; then
    echo "Start must fail without quickshell" >&2
    exit 1
fi
[[ ! -e "$FIXTURE/waybar.running" && ! -e "$FIXTURE/quickshell.log" ]]
mv "$HOME/.config/quickshell/pilot/shell.qml" "$FIXTURE/shell.qml.bak"
if run start 2>/dev/null; then
    echo "Start must fail without the config" >&2
    exit 1
fi
mv "$FIXTURE/shell.qml.bak" "$HOME/.config/quickshell/pilot/shell.qml"
if env -u WAYLAND_DISPLAY bash "$helper" start 2>/dev/null; then
    echo "Start must fail without Wayland" >&2
    exit 1
fi
[[ ! -e "$FIXTURE/waybar.running" && ! -e "$FIXTURE/quickshell.log" ]]

# Unknown action.
if run bogus 2>/dev/null; then
    echo "Unknown action should fail" >&2
    exit 1
fi

echo 'hypr-quickshell-pilot: all cases passed'
