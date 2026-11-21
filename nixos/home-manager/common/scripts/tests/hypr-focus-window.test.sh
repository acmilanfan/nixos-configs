#!/usr/bin/env bash
set -euo pipefail

script=$(dirname "$0")/../hypr-focus-window
scratch="$HOME/ai/artifacts/nixos-configs/hyprland-mac-keybinds"
mkdir -p "$scratch"
export FIXTURE
FIXTURE=$(mktemp -d "$scratch/picker.XXXXXX")
trap 'rm -f "$FIXTURE/"{hyprctl,vicinae,initial,current,rows,dispatch,eval.lua}; rmdir "$FIXTURE"' EXIT
export PATH="$FIXTURE:$PATH"

cat > "$FIXTURE/hyprctl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    '-j clients'|'clients -j') cat "$FIXTURE/initial" ;;
    dispatch\ *) printf '%s\n' "$2" >> "$FIXTURE/dispatch" ;;
    eval\ *) HYPR_TEST_EXPRESSION="$2" nvim --headless -u NONE -l "$FIXTURE/eval.lua" ;;
    *) exit 2 ;;
esac
EOF
cat > "$FIXTURE/vicinae" <<'EOF'
#!/usr/bin/env bash
cat > "$FIXTURE/rows"
case "$CHOICE" in
    cancel) exit 1 ;;
    bogus) printf '%s\n' 'unoffered row' ;;
    *) sed -n "${CHOICE}p" "$FIXTURE/rows" ;;
esac
EOF
cat > "$FIXTURE/eval.lua" <<'EOF'
local root = vim.env.FIXTURE
local windows = vim.json.decode(table.concat(vim.fn.readfile(root .. "/current"), "\n"))
hl = {
    get_window = function(selector)
        for _, w in ipairs(windows) do
            if selector == "address:" .. w.address then
                return { address = w.address, stable_id = tonumber(w.stableId, 16) }
            end
        end
    end,
    dsp = { focus = function(args) return assert(args.window) end },
    dispatch = function(window)
        vim.fn.writefile({ assert(window.address) }, root .. "/dispatch", "a")
    end,
}
assert(loadstring(vim.env.HYPR_TEST_EXPRESSION))()
EOF
chmod +x "$FIXTURE/"{hyprctl,vicinae}
printf '%s\n' '[{"class":"Firefox","title":"Same\tname\nhere","pid":42,"address":"0xabc","stableId":"18000001"},{"class":"Firefox","title":"Same\tname\nhere","pid":42,"address":"0xdef","stableId":"18000002"}]' > "$FIXTURE/initial"
cp "$FIXTURE/initial" "$FIXTURE/current"

run() {
    rm -f "$FIXTURE/"{dispatch,rows}
    CHOICE="$1" bash "$script"
}
no_focus() {
    if [[ -e "$FIXTURE/dispatch" ]]; then
        echo "Unexpected focus: $(cat "$FIXTURE/dispatch")" >&2
        exit 1
    fi
}

run 2
expected="0xdef"
actual=$(cat "$FIXTURE/dispatch")
[[ "$actual" == "$expected" ]] || { echo "Expected exact window, got: $actual" >&2; exit 1; }
[[ $(cat "$FIXTURE/rows") == $'1. Firefox: Same name here\n2. Firefox: Same name here' ]]
jq '.[1].stableId = "1800000a"' "$FIXTURE/initial" > "$FIXTURE/current"
cp "$FIXTURE/current" "$FIXTURE/initial"
run 2
[[ -e "$FIXTURE/dispatch" && $(cat "$FIXTURE/dispatch") == "$expected" ]] ||
    { echo "Expected focus for a hexadecimal ID" >&2; exit 1; }
run cancel
no_focus
run bogus
no_focus
printf '%s\n' '[]' > "$FIXTURE/current"
run 2
no_focus
jq '.[1].stableId = "18000003"' "$FIXTURE/initial" > "$FIXTURE/current"
run 2
no_focus
jq 'map(del(.address))' "$FIXTURE/initial" > "$FIXTURE/current"
cp "$FIXTURE/current" "$FIXTURE/initial"
run 1
no_focus
printf '%s\n' '[]' > "$FIXTURE/initial"
run 1
no_focus
[[ ! -e "$FIXTURE/rows" ]]
echo 'hypr-focus-window: all cases passed'
