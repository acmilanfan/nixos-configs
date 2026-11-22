#!/usr/bin/env bash
set -euo pipefail

helper=$(dirname "$0")/../hypr-firefox-tabs
scratch="$HOME/ai/artifacts/nixos-configs/hammerspoon-parity"
mkdir -p "$scratch"
export FIXTURE
FIXTURE=$(mktemp -d "$scratch/fftabs.XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT
export PATH="$FIXTURE:$PATH"

cat > "$FIXTURE/wtype" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FIXTURE/wtype.log"
EOF
chmod +x "$FIXTURE/wtype"

check() {
    local action=$1 expected=$2
    rm -f "$FIXTURE/wtype.log"
    bash "$helper" "$action"
    [[ $(cat "$FIXTURE/wtype.log") == "$expected" ]] ||
        { echo "$action: got $(cat "$FIXTURE/wtype.log")" >&2; exit 1; }
}

check next '-M ctrl -k Tab'
check prev '-M ctrl -M shift -k Tab'
check toggle '-M ctrl -M alt -k z'

rm -f "$FIXTURE/wtype.log"
if bash "$helper" bogus 2>/dev/null; then
    echo "Unknown action should fail" >&2
    exit 1
fi
[[ ! -e "$FIXTURE/wtype.log" ]] || { echo 'Unknown action sent keys' >&2; exit 1; }

echo 'hypr-firefox-tabs: all cases passed'
