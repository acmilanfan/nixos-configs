#!/usr/bin/env bash
set -euo pipefail

helper=$(dirname "$0")/../hypr-quickshell-shell
scratch="$HOME/ai/artifacts/nixos-configs/quickshell-shell"
mkdir -p "$scratch"
export FIXTURE
FIXTURE=$(mktemp -d "$scratch/helper.XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT
export HOME="$FIXTURE/home"
mkdir -p "$HOME/.config/quickshell/shell"
touch "$HOME/.config/quickshell/shell/shell.qml"
export PATH="$FIXTURE:$PATH"
export WAYLAND_DISPLAY=wayland-test

cat > "$FIXTURE/pgrep" <<'EOF'
#!/usr/bin/env bash
case "$2" in
    *quickshell*) [[ -e "$FIXTURE/shell.running" ]] ;;
    *) exit 1 ;;
esac
EOF
cat > "$FIXTURE/pkill" <<'EOF'
#!/usr/bin/env bash
case "$2" in
    *quickshell*) rm -f "$FIXTURE/shell.running" ;;
    *) exit 1 ;;
esac
EOF
cat > "$FIXTURE/setsid" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
cat > "$FIXTURE/systemctl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    "--user is-enabled"*) [[ -e "$FIXTURE/service.enabled" ]] ;;
    "--user is-active"*) [[ -e "$FIXTURE/shell.running" ]] ;;
    "--user start"*) printf 'start\n' >> "$FIXTURE/systemctl.log"; touch "$FIXTURE/shell.running" ;;
    "--user stop"*) printf 'stop\n' >> "$FIXTURE/systemctl.log"; rm -f "$FIXTURE/shell.running" ;;
    "--user restart"*) printf 'restart\n' >> "$FIXTURE/systemctl.log"; touch "$FIXTURE/shell.running" ;;
    *) exit 1 ;;
esac
EOF
cat > "$FIXTURE/quickshell" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FIXTURE/quickshell.log"
touch "$FIXTURE/shell.running"
EOF
cat > "$FIXTURE/hypr-waybar-toggle" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FIXTURE/waybar.log"
EOF
chmod +x "$FIXTURE"/{pgrep,pkill,setsid,quickshell,hypr-waybar-toggle,systemctl}

reset() { rm -f "$FIXTURE"/*.running "$FIXTURE"/*.log; }
run() { bash "$helper" "$@"; }
wait_for() {
    for _ in $(seq 100); do [[ -e "$1" ]] && return 0; sleep 0.02; done
    echo "Timed out waiting for $1" >&2
    exit 1
}

reset
run status | grep -qx 'quickshell shell: stopped'

run start
wait_for "$FIXTURE/quickshell.log"
grep -qx -- '-c shell' "$FIXTURE/quickshell.log"
grep -qx 'off' "$FIXTURE/waybar.log"

run start
[[ $(grep -c . "$FIXTURE/quickshell.log") == 1 ]]

run stop
grep -qx 'on' "$FIXTURE/waybar.log"
[[ ! -e "$FIXTURE/shell.running" ]]

reset
touch "$FIXTURE/shell.running"
run restart
wait_for "$FIXTURE/quickshell.log"
grep -qx 'off' "$FIXTURE/waybar.log"

reset
run toggle
wait_for "$FIXTURE/shell.running"
run toggle
[[ ! -e "$FIXTURE/shell.running" ]]
grep -qx 'on' "$FIXTURE/waybar.log"

# Failed starts must leave Waybar untouched.
reset
mkdir -p "$FIXTURE/nobin"
for cmd in pgrep pkill setsid hypr-waybar-toggle; do ln -s "$FIXTURE/$cmd" "$FIXTURE/nobin/$cmd"; done
ln -s "$(command -v bash)" "$FIXTURE/nobin/bash"
if PATH="$FIXTURE/nobin:/usr/bin:/bin" run start 2>/dev/null; then
    echo "Start must fail without quickshell" >&2
    exit 1
fi
grep -qx 'on' "$FIXTURE/waybar.log"
[[ ! -e "$FIXTURE/quickshell.log" ]]
if env -u WAYLAND_DISPLAY bash "$helper" start 2>/dev/null; then
    echo "Start must fail without Wayland" >&2
    exit 1
fi
grep -qx 'on' "$FIXTURE/waybar.log"

# With the systemd unit enabled, the helper delegates to it.
reset
touch "$FIXTURE/service.enabled"
run start
grep -qx 'start' "$FIXTURE/systemctl.log"
[[ ! -e "$FIXTURE/quickshell.log" ]]
run status | grep -qx 'quickshell shell: running'
run stop
grep -qx 'stop' "$FIXTURE/systemctl.log"
[[ ! -e "$FIXTURE/shell.running" ]]
rm -f "$FIXTURE/service.enabled"

if run bogus 2>/dev/null; then
    echo "Unknown action should fail" >&2
    exit 1
fi

echo 'hypr-quickshell-shell: all cases passed'
