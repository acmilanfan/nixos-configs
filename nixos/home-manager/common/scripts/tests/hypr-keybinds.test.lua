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
check(":alt + shift + h", "exec_cmd", "hypr-window-adapt h")
check(":alt + shift + l", "exec_cmd", "hypr-window-adapt l")
check(":alt + shift + j", "exec_cmd", "hypr-window-adapt j")
check(":alt + shift + k", "exec_cmd", "hypr-window-adapt k")
check(":alt + ctrl + h", "layout", "orientationright")
check(":alt + ctrl + l", "layout", "orientationleft")
check(":alt + ctrl + j", "layout", "orientationright")
check(":alt + ctrl + k", "layout", "orientationleft")
assert(flags(":alt + h").repeating and flags(":alt + l").repeating)
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

check(":alt + comma", "submap", "leader")
check("leader:c", "submap", "leader-controls")
for key, original in pairs({ w = ":alt + ctrl + b", b = ":alt + shift + b", m = ":alt + shift + i" }) do
  equal(invoke("leader-controls:" .. key), {
    { name = "submap", args = "reset" }, get(original),
  }, "leader-controls:" .. key)
end
for _, key in ipairs({ "escape", "q" }) do
  check("leader:" .. key, "submap", "reset")
  equal(invoke("leader-controls:" .. key), { { name = "submap", args = "reset" } }, key)
end
for key, cmd in pairs({t = "alacritty", b = "firefox", r = "hyprctl reload", k = "hypr-ai-agents --menu"}) do
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
  { name = "exec_cmd", args = "hypr-firefox-tabs toggle" },
  { name = "submap", args = "firefox-tabs" },
}, "firefox toggle")
assert(ff_result == nil)
local other_calls, other_result = firefox_toggle({ class = "Alacritty" })
equal(other_calls, {}, "non-firefox pass-through")
equal(other_result, { ok = false }, "non-firefox result")

for _, key in ipairs({ "j", "down" }) do
  equal(invoke("firefox-tabs:" .. key), { { name = "exec_cmd", args = "hypr-firefox-tabs next" } }, "firefox-tabs:" .. key)
  assert(flags("firefox-tabs:" .. key).repeating)
end
for _, key in ipairs({ "k", "up" }) do
  equal(invoke("firefox-tabs:" .. key), { { name = "exec_cmd", args = "hypr-firefox-tabs prev" } }, "firefox-tabs:" .. key)
  assert(flags("firefox-tabs:" .. key).repeating)
end
for _, key in ipairs({ "return", "escape", "ctrl + alt + z" }) do
  equal(invoke("firefox-tabs:" .. key), {
    { name = "exec_cmd", args = "hypr-firefox-tabs toggle" },
    { name = "submap", args = "reset" },
  }, "firefox-tabs:" .. key)
end
check("firefox-tabs:catchall", "submap", "reset")
assert(flags("firefox-tabs:catchall").non_consuming)

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
