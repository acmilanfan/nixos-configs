-- Run with nvim --headless -u NONE -l <this file> from the repo root.
local binds, calls, scope = {}, {}, ""
local state = { window = nil, submap = "" }
local handlers = {}
local function noop() end
local function dispatcher(path)
  return setmetatable({}, {
    __index = function(_, key) return dispatcher(path .. key .. ".") end,
    __call = function(_, args) return { name = path:sub(1, -2), args = args } end,
  })
end

hl = setmetatable({
  dsp = dispatcher(""),
  bind = function(key, action, flags)
    key = scope .. ":" .. key:lower()
    binds[key] = binds[key] or {}
    table.insert(binds[key], { action = action, flags = flags or {} })
  end,
  define_submap = function(name, fn)
    local previous = scope
    scope = name
    fn()
    scope = previous
  end,
  dispatch = function(action) table.insert(calls, action) end,
  exec_cmd = function(cmd) table.insert(calls, { name = "exec_cmd", args = cmd }) end,
  get_active_window = function() return state.window end,
  get_current_submap = function() return state.submap end,
  on = function(name, fn) handlers[name] = fn end,
}, { __index = function() return noop end })

dofile("dotfiles/hypr/hyprland.lua")
dofile("dotfiles/hypr/touch-gestures.lua")

local function get(key)
  local list = binds[key] or {}
  assert(#list == 1, key .. ": expected one bind, got " .. #list)
  return list[1].action
end
local function flags(key)
  local list = binds[key] or {}
  assert(#list == 1, key .. ": expected one bind, got " .. #list)
  return list[1].flags
end
local function equal(actual, expected, key)
  assert(vim.deep_equal(actual, expected), key .. ": got " .. vim.inspect(actual))
end
local function check(key, name, args)
  equal(get(key), { name = name, args = args }, key)
end
local function invoke(key)
  calls = {}
  local action = get(key)
  if type(action) == "function" then action() else hl.dispatch(action) end
  return calls
end

check(":alt + shift + space", "window.float", { action = "toggle" })
check(":alt + shift + 0", "window.move", { workspace = "10" })
check(":alt + shift + minus", "exec_cmd", "hyprctl -q keyword cursor:zoom_factor 1")
check(":alt + r", "layout", "colresize +conf")
check(":alt + x", "exec_cmd", "hypr-bar-toggle top")
check(":alt + shift + x", "exec_cmd", "hypr-bar-toggle bottom")
check(":alt + ctrl + x", "exec_cmd", "hypr-bar-toggle external")
check(":alt + shift + ctrl + x", "exec_cmd", "hypr-bar-toggle all")
check(":alt + ctrl + h", "layout", "orientationright")
check(":alt + ctrl + l", "layout", "orientationleft")
check(":alt + ctrl + j", "layout", "orientationright")
check(":alt + ctrl + k", "layout", "orientationleft")
assert(flags(":alt + h").repeating and flags(":alt + l").repeating)
local function invoke_window(key, window)
  calls = {}
  state.window = window
  local action = get(key)
  assert(type(action) == "function", key .. " should be a function")
  action()
  return calls
end
for key, step in pairs({ h = { -40, 0 }, l = { 40, 0 }, k = { 0, -40 }, j = { 0, 40 } }) do
  equal(invoke_window(":alt + shift + " .. key, { floating = true }), {
    { name = "window.resize", args = { x = step[1], y = step[2], relative = true } },
  }, "floating " .. key)
end
for key, nxt in pairs({ h = false, k = false, l = true, j = true }) do
  equal(invoke_window(":alt + shift + " .. key, { floating = false }), {
    { name = "window.swap", args = nxt and { next = true } or { prev = true } },
  }, "tiled " .. key)
end
check(":alt + p", "exec_cmd", "hypr-commands")
check(":alt + slash", "exec_cmd", "hypr-commands")
check(":alt + i", "exec_cmd", "hypr-focus-window")
check(":alt + a", "exec_cmd", "hypr-ai-agents --menu")
check(":alt + y", "exec_cmd",
  [[hypr-focus-or-spawn yazi YAZI "alacritty --class yazi --title YAZI -e yazi"]])
assert(get(":alt + ctrl + a").args:find("moveworkspacetomonitor", 1, true))
check(":alt + space", "exec_cmd", "hypr-touch-menu")
check(":alt + n", "exec_cmd", "swaync-client -t -sw")
check(":super + t", "exec_cmd", "yb-touchpad window")
check(":super + m", "exec_cmd", "yb-mode cycle")
assert(not binds[":alt + tab"] and not binds[":super + space"])
for n = 1, 10 do
  local key = n % 10
  check(":alt + " .. key, "focus", { workspace = tostring(n) })
  check(":alt + ctrl + " .. key, "focus", { workspace = tostring(n + 10) })
end

local leader_entry = invoke(":alt + comma")
assert(leader_entry[1].name == "exec_cmd" and leader_entry[1].args:find("notify%-send"))
equal(leader_entry[2], { name = "submap", args = "leader" }, ":alt + comma")
local controls_entry = invoke("leader:c")
assert(controls_entry[1].name == "exec_cmd" and controls_entry[1].args:find("notify%-send"))
equal(controls_entry[2], { name = "submap", args = "leader-controls" }, "leader:c")

-- Timer mode
local timer_entry = invoke(":alt + t")
assert(timer_entry[1].name == "exec_cmd" and timer_entry[1].args:find("notify%-send"))
equal(timer_entry[2], { name = "submap", args = "timer" }, ":alt + t")
for key, minutes in pairs({ ["1"] = 5, ["2"] = 10, ["3"] = 60, ["4"] = 120 }) do
  equal(invoke("timer:" .. key), {
    { name = "exec_cmd", args = "hypr-timer start " .. minutes },
    { name = "submap", args = "reset" },
  }, "timer:" .. key)
end
equal(invoke("timer:n"), {
  { name = "exec_cmd", args = "hypr-timer prompt" },
  { name = "submap", args = "reset" },
}, "timer:n")
equal(invoke("timer:r"), {
  { name = "exec_cmd", args = "hypr-timer notify" },
  { name = "submap", args = "reset" },
}, "timer:r")
equal(invoke("timer:c"), {
  { name = "exec_cmd", args = "hypr-timer stop" },
  { name = "submap", args = "reset" },
}, "timer:c")
for _, key in ipairs({ "escape", "q" }) do
  check("timer:" .. key, "submap", "reset")
end
check("timer:catchall", "submap", "reset")
assert(flags("timer:catchall").non_consuming and flags("timer:catchall").ignore_mods)
for key, original in pairs({ w = ":alt + ctrl + b", b = ":alt + shift + b", m = ":alt + shift + i" }) do
  equal(invoke("leader-controls:" .. key), {
    { name = "submap", args = "reset" }, get(original),
  }, "leader-controls:" .. key)
end
for _, key in ipairs({ "escape", "q" }) do
  check("leader:" .. key, "submap", "reset")
  equal(invoke("leader-controls:" .. key), { { name = "submap", args = "reset" } }, key)
end
for key, cmd in pairs({t = "ghostty", b = "firefox", r = "hyprctl reload", k = "hypr-ai-agents --menu"}) do
  equal(invoke("leader:" .. key), {
    { name = "exec_cmd", args = cmd }, { name = "submap", args = "reset" },
  }, "leader:" .. key)
end
equal(invoke("leader:v")[1], { name = "submap", args = "vim-mode" }, "leader:v")

-- Firefox tab mode
assert(flags(":ctrl + alt + z").auto_consuming)
assert(type(get(":ctrl + alt + z")) == "function")
local function firefox_toggle(window)
  calls = {}
  state.window = window
  local result = get(":ctrl + alt + z")()
  return calls, result
end
local ff_calls, ff_result = firefox_toggle({ class = "firefox" })
equal(ff_calls, {
  { name = "send_shortcut", args = { mods = "CTRL ALT", key = "z", window = "activewindow" } },
  { name = "submap", args = "firefox-tabs" },
}, "firefox toggle")
assert(ff_result == nil)
local other_calls, other_result = firefox_toggle({ class = "Alacritty" })
equal(other_calls, {}, "non-firefox pass-through")
equal(other_result, { ok = false }, "non-firefox result")

for _, key in ipairs({ "j", "down" }) do
  equal(invoke("firefox-tabs:" .. key), {
    { name = "send_shortcut", args = { mods = "CTRL", key = "Tab", window = "activewindow" } },
  }, "firefox-tabs:" .. key)
  assert(flags("firefox-tabs:" .. key).repeating)
end
for _, key in ipairs({ "k", "up" }) do
  equal(invoke("firefox-tabs:" .. key), {
    { name = "send_shortcut", args = { mods = "CTRL SHIFT", key = "Tab", window = "activewindow" } },
  }, "firefox-tabs:" .. key)
  assert(flags("firefox-tabs:" .. key).repeating)
end
for _, key in ipairs({ "return", "escape", "ctrl + alt + z" }) do
  equal(invoke("firefox-tabs:" .. key), {
    { name = "send_shortcut", args = { mods = "CTRL ALT", key = "z", window = "activewindow" } },
    { name = "submap", args = "reset" },
  }, "firefox-tabs:" .. key)
end
check("firefox-tabs:catchall", "submap", "reset")
assert(flags("firefox-tabs:catchall").non_consuming and flags("firefox-tabs:catchall").ignore_mods)

local function focus_away(window, submap)
  calls = {}
  state.submap = submap
  handlers["window.active"](window)
  return calls
end
equal(focus_away({ class = "Alacritty" }, "firefox-tabs"), { { name = "submap", args = "reset" } }, "focus away")
equal(focus_away({ class = "firefox" }, "firefox-tabs"), {}, "firefox keeps mode")
equal(focus_away({ class = "Alacritty" }, "vim-mode"), {}, "leave other submap")

print("hypr-keybinds: all cases passed")
