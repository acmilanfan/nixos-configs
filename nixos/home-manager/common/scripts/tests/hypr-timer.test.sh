#!/usr/bin/env bash
set -euo pipefail

script=$(dirname "$0")/../hypr-timer
scratch="$HOME/ai/artifacts/nixos-configs/leader-timer"
mkdir -p "$scratch"
export FIXTURE
FIXTURE=$(mktemp -d "$scratch/timer.XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT
export XDG_RUNTIME_DIR="$FIXTURE/run"
mkdir -p "$XDG_RUNTIME_DIR"
export PATH="$FIXTURE:$PATH"

cat > "$FIXTURE/vicinae" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$CHOICE"
EOF
cat > "$FIXTURE/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FIXTURE/notify.log"
EOF
chmod +x "$FIXTURE"/{vicinae,notify-send}
state="$XDG_RUNTIME_DIR/hypr-timer.json"

run() { bash "$script" "$@"; }

# Prompt accepts a positive integer.
rm -f "$state" "$FIXTURE/notify.log"
CHOICE=7 run prompt
[[ $(jq -r '.running' "$state") == true ]]
[[ $(jq -r '.duration' "$state") == 420 ]]

# Prompt rejects empty and non-numeric input.
for choice in '' abc 0 -3; do
    rm -f "$state"
    CHOICE="$choice" run prompt
    [[ ! -e "$state" ]] || { echo "Accepted invalid prompt '$choice'" >&2; exit 1; }
done

# Notify reports the running timer, or that none is running.
rm -f "$state" "$FIXTURE/notify.log"
run notify
grep -q 'No timer running' "$FIXTURE/notify.log"
run start 5
: > "$FIXTURE/notify.log"
run notify
grep -q 'Remaining:' "$FIXTURE/notify.log"

# Existing lifecycle still works.
run stop
[[ $(jq -r '.running' "$state") == false ]]
run reset
[[ ! -e "$state" ]]

echo 'hypr-timer: all cases passed'
