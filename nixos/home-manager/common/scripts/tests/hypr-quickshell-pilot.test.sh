#!/usr/bin/env bash
set -euo pipefail

helper=$(dirname "$0")/../hypr-quickshell-pilot
scratch="$HOME/ai/artifacts/nixos-configs/quickshell-pilot"
mkdir -p "$scratch"
export FIXTURE
FIXTURE=$(mktemp -d "$scratch/helper.XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT
export PATH="$FIXTURE:$PATH"

cat > "$FIXTURE/pgrep" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    '-f quickshell -c pilot') [[ -e "$FIXTURE/qs.running" ]] ;;
    '-f waybar -c .*config-hypr-bottom') [[ -e "$FIXTURE/waybar.running" ]] ;;
    *) exit 1 ;;
esac
EOF
cat > "$FIXTURE/pkill" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    '-f quickshell -c pilot') rm -f "$FIXTURE/qs.running" ;;
    '-f waybar -c .*config-hypr-bottom') rm -f "$FIXTURE/waybar.running" ;;
    *) exit 1 ;;
esac
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
chmod +x "$FIXTURE"/{pgrep,pkill,setsid,quickshell,waybar}

reset() { rm -f "$FIXTURE"/*.running "$FIXTURE"/*.log; }
run() { bash "$helper" "$@"; }
wait_for() {
    for _ in $(seq 100); do [[ -e "$1" ]] && return 0; sleep 0.02; done
    echo "Timed out waiting for $1" >&2
    exit 1
}

reset
run status | grep -qx 'quickshell pilot: stopped'
run start
wait_for "$FIXTURE/quickshell.log"
grep -qx -- '-c pilot' "$FIXTURE/quickshell.log"
[[ ! -e "$FIXTURE/waybar.log" ]]
run start
[[ $(grep -c . "$FIXTURE/quickshell.log") == 1 ]]
run status | grep -qx 'quickshell pilot: running'

run stop
wait_for "$FIXTURE/waybar.log"
[[ ! -e "$FIXTURE/qs.running" ]]
grep -q -- '-c .*config-hypr-bottom' "$FIXTURE/waybar.log"
grep -q -- '-s .*style-hypr.css' "$FIXTURE/waybar.log"

reset
run toggle
wait_for "$FIXTURE/qs.running"
run toggle
wait_for "$FIXTURE/waybar.running"
[[ ! -e "$FIXTURE/qs.running" ]]

reset
if run bogus 2>/dev/null; then
    echo "Unknown action should fail" >&2
    exit 1
fi
[[ ! -e "$FIXTURE/quickshell.log" && ! -e "$FIXTURE/waybar.log" ]]

echo 'hypr-quickshell-pilot: all cases passed'
