-- Run with nvim --headless -u NONE -l <this file> from the repo root.
local binds, calls, scope = {}, {}, ""
local function noop() end
local function dispatcher(path)
  return setmetatable({}, {
    __index = function(_, key) return dispatcher(path .. key .. ".") end,
    __call = function(_, args) return { name = path:sub(1, -2), args = args } end,
  })
end

hl = setmetatable({
  dsp = dispatcher(""),
  bind = function(key, action)
    key = scope .. ":" .. key:lower()
    binds[key] = binds[key] or {}
    table.insert(binds[key], action)
  end,
  define_submap = function(name, fn)
    local previous = scope
    scope = name
    fn()
    scope = previous
  end,
  dispatch = function(action) table.insert(calls, action) end,
  exec_cmd = function(cmd) table.insert(calls, { name = "exec_cmd", args = cmd }) end,
}, { __index = function() return noop end })

dofile("dotfiles/hypr/hyprland.lua")
dofile("dotfiles/hypr/touch-gestures.lua")

local function get(key)
  local list = binds[key] or {}
  assert(#list == 1, key .. ": expected one bind, got " .. #list)
  return list[1]
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
check(":alt + p", "exec_cmd", "hypr-commands")
check(":alt + slash", "exec_cmd", "hypr-commands")
check(":alt + i", "exec_cmd", "hypr-focus-window")
check(":alt + a", "exec_cmd", "hypr-ai-agents --menu")
assert(get(":alt + ctrl + a").args:find("moveworkspacetomonitor", 1, true))
check(":alt + space", "exec_cmd", "hypr-touch-menu")
check(":alt + n", "exec_cmd", "swaync-client -t -sw")
check(":super + t", "exec_cmd", "yb-touchpad window")
check(":super + m", "exec_cmd", "hypr-touchpad-mode")
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
print("hypr-keybinds: all cases passed")
