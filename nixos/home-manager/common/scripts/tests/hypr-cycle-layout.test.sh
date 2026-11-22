#!/usr/bin/env bash
set -euo pipefail

script=$(dirname "$0")/../hypr-cycle-layout
scratch="$HOME/ai/artifacts/nixos-configs/leader-timer"
mkdir -p "$scratch"
export FIXTURE
FIXTURE=$(mktemp -d "$scratch/layout.XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT
export PATH="$FIXTURE:$PATH"

cat > "$FIXTURE/hyprctl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    '-j activeworkspace') printf '{"layout":"%s"}\n' "$(cat "$FIXTURE/layout")" ;;
    eval\ *) printf '%s\n' "${*:2}" >> "$FIXTURE/evals" ;;
    *) exit 2 ;;
esac
EOF
chmod +x "$FIXTURE/hyprctl"

check() {
    local from=$1 expected=$2
    printf '%s\n' "$from" > "$FIXTURE/layout"
    : > "$FIXTURE/evals"
    bash "$script"
    [[ $(cat "$FIXTURE/evals") == "$expected" ]] ||
        { echo "$from: got $(cat "$FIXTURE/evals")" >&2; exit 1; }
}

check master "hl.config({general={layout='dwindle'}})"
check dwindle "hl.config({general={layout='scrolling'}})"
check scrolling "hl.config({general={layout='master'}})"
check unknown "hl.config({general={layout='master'}})"

echo 'hypr-cycle-layout: all cases passed'
