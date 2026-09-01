local mod = "ALT"
local terminal = "alacritty"
local browser = "firefox"

-- --- ENVIRONMENT ---
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("XCURSOR_SIZE", "28")
hl.env("HYPRCURSOR_SIZE", "28")
-- macOS-style stem darkening for FreeType
hl.env("FREETYPE_PROPERTIES", "cff:no-stem-darkening=0 autofitter:no-stem-darkening=0 type1:no-stem-darkening=0 t1cid:no-stem-darkening=0")

-- --- MONITORS ---
-- Not predefined: auto-detect on startup, then hypr-profile restore applies the saved layout.
-- Scripts manage monitors via hyprctl eval hl.monitor().

-- --- DEVICE CONFIG ---
hl.device({
  name = "ingenic-gadget-serial-and-keyboard-touchscreen-top",
  output = "eDP-1",
})

hl.device({
  name = "ingenic-gadget-serial-and-keyboard-stylus-top",
  output = "eDP-1",
})

hl.device({
  name = "ingenic-gadget-serial-and-keyboard-touchscreen-bottom",
  output = "eDP-2",
})

hl.device({
  name = "ingenic-gadget-serial-and-keyboard-stylus-bottom",
  output = "eDP-2",
})

hl.device({
  name = "bastard-keyboards-charybdis-nano-(3x5)-splinky",
  repeat_delay = 200,
  repeat_rate = 45,
})

hl.device({
  name = "aurora-sweep-keyboard",
  repeat_delay = 200,
  repeat_rate = 45,
})

-- --- CONFIG ---
hl.config({
  input = {
    kb_layout = "us,de,ru",
    follow_mouse = 1,
    kb_options = "grp:lctrl_lshift_toggle",
    touchpad = {
      natural_scroll = true,
    },
  },

  cursor = {
    inactive_timeout = 5,
    hide_on_key_press = true,
    no_hardware_cursors = true,
  },

  -- misc = {
  --   vrr = 1,
  -- },

  general = {
    gaps_in = 3,
    gaps_out = 5,
    border_size = 2,
    ["col.active_border"] = "#734899",
    ["col.inactive_border"] = "rgba(0,0,0,0.667)",
    layout = "master",
    allow_tearing = false,
  },

  master = {
    mfact = 0.5,
    new_status = "master",
  },

  decoration = {
    rounding = 6,
    blur = {
      enabled = false,
    },
  },

  animations = {
    enabled = true,
  },
})

-- Animation curves
hl.curve("ease", { type = "bezier", points = { {0.4, 0.02}, {0.21, 1} } })

-- Animation presets (all use the built-in "default" bezier)
hl.animation({ leaf = "windows", enabled = true, speed = 1, bezier = "default" })
hl.animation({ leaf = "fade", enabled = true, speed = 1, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1, bezier = "default" })
hl.animation({ leaf = "zoomFactor", enabled = true, speed = 4, bezier = "default" })

hl.config({
  binds = {
    pass_mouse_when_bound = false,
  },
})

-- --- AUTOSTART ---
hl.on("hyprland.start", function()
  hl.exec_cmd("swww init")
  hl.exec_cmd("swww img ~/.config/hypr/wallpapers/default.jpg")
  hl.exec_cmd("hypr-waybar-toggle on")
  hl.exec_cmd("nm-applet")
  hl.exec_cmd("hyprctl setcursor breeze_cursors 28")
  hl.exec_cmd("hypr-profile restore")
  hl.exec_cmd("bash -c 'sleep 3 && sync-volume'")
  hl.exec_cmd("bash -c 'sleep 4 && brightness-ctl restore &'")
  hl.exec_cmd("ln -sf /run/user/1000/ssh-agent ~/.ssh/ssh_auth_sock")
  hl.exec_cmd("ssh-add-login")
end)

-- --- WORKSPACE RULES: Bottom screen (eDP-2) ---
for i = 1, 10 do
  hl.workspace_rule({ workspace = tostring(i), monitor = "eDP-2" })
end

-- --- WORKSPACE RULES: Top screen (eDP-1) ---
for i = 11, 20 do
  hl.workspace_rule({ workspace = tostring(i), monitor = "eDP-1" })
end

-- ================================================================================
-- --- EMBEDDED TOGGLE FUNCTIONS (replaces shell scripts for keybind paths) ---
-- ================================================================================

-- toggle_powersave: no subprocess for "on", reload for "off"
local _powersave = false
function _toggle_powersave()
  if _powersave then
    hl.exec_cmd("hyprctl reload")
    hl.exec_cmd('hyprctl notify 1 5000 "rgb(d20f39)" "Powersave mode [OFF]"')
    _powersave = false
  else
    hl.config({
      animations = { enabled = false },
      decoration = {
        shadow = { enabled = false },
        blur = { enabled = false },
        fullscreen_opacity = 1,
        rounding = 0,
      },
      general = {
        gaps_in = 0,
        gaps_out = 0,
        border_size = 1,
      },
    })
    hl.exec_cmd('hyprctl notify 1 5000 "rgb(40a02b)" "Powersave mode [ON]"')
    _powersave = true
  end
end

-- toggle_animations: hl.config() for "off", reload for "on"
local _anims_off = false
function _toggle_animations()
  if _anims_off then
    hl.exec_cmd("hyprctl reload")
    hl.exec_cmd('hyprctl notify 1 5000 "rgb(d20f39)" "Animations ON"')
    _anims_off = false
  else
    hl.config({ animations = { enabled = false } })
    hl.exec_cmd('hyprctl notify 1 5000 "rgb(40a02b)" "Animations OFF"')
    _anims_off = true
  end
end

-- ================================================================================
-- --- KEYBINDS ---
-- ================================================================================

-- Launch apps
hl.bind(mod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + B", hl.dsp.exec_cmd(browser))
hl.bind(mod .. " + D", hl.dsp.exec_cmd("fuzzel --hide-before-typing --show-actions"))
hl.bind(mod .. " + CTRL + D", hl.dsp.exec_cmd("vicinae toggle"))
hl.bind(mod .. " + SHIFT + T", hl.dsp.exec_cmd("rofi -show top -modi top"))
hl.bind(mod .. " + SHIFT + P", hl.dsp.exec_cmd("wlogout"))
hl.bind(mod .. " + SHIFT + B", hl.dsp.exec_cmd("bzmenu -l fuzzel"))
hl.bind(mod .. " + CTRL + B", hl.dsp.exec_cmd("iwmenu -l fuzzel"))
hl.bind(mod .. " + CTRL + S", hl.dsp.exec_cmd("rofi-systemd"))
hl.bind(mod .. " + SHIFT + I", hl.dsp.exec_cmd("pwmenu -l fuzzel"))
hl.bind("CTRL + SHIFT + I", hl.dsp.exec_cmd('BEMOJI_PICKER_CMD="fuzzel -d -p Emoji:" bemoji'))
hl.bind(mod .. " + SUPER + C", hl.dsp.exec_cmd("rofi -show calc -modi calc -no-show-match -no-sort"))
hl.bind(mod .. " + SHIFT + V", hl.dsp.exec_cmd("cliphist-fuzzel-img"))

hl.bind(mod .. " + SHIFT + CTRL + SUPER + L", hl.dsp.exec_cmd("hyprlock"))

hl.bind("CTRL + SHIFT + S", hl.dsp.exec_cmd("hypr-profile"))
hl.bind(mod .. " + X", hl.dsp.exec_cmd('pkill -USR1 -f "waybar.*top"'))
hl.bind(mod .. " + SHIFT + X", hl.dsp.exec_cmd('pkill -USR1 -f "waybar.*bottom"'))
hl.bind(mod .. " + CTRL + X", hl.dsp.exec_cmd('pkill -USR1 -f "waybar.*external"'))
hl.bind(mod .. " + SHIFT + CTRL + X", hl.dsp.exec_cmd("hypr-waybar-toggle"))

-- Orgmode/terminal
hl.bind(mod .. " + SHIFT + O", function()
  hl.dispatch(hl.dsp.exec_cmd([=[hypr-focus-or-spawn orgindex AGENDA "alacritty -o 'window.dimensions.lines=20' -o 'window.dimensions.columns=100' --class orgindex --title ORGINDEX-AGENDA -e zsh -c 'nvim --cmd \"cd ~/org/life\" -c \"lua require(\\\"orgmode.api.agenda\\\").agenda({span = 1})\" -c \"autocmd VimEnter * ++once lua vim.defer_fn(function() for _, buf in ipairs(vim.api.nvim_list_bufs()) do if vim.api.nvim_buf_get_option(buf, \\\"filetype\\\") ~= \\\"orgagenda\\\" then vim.api.nvim_buf_delete(buf, {force = true}) end end end, 200)\"'"]=]))
end)

hl.bind(mod .. " + SHIFT + W", function()
  hl.dispatch(hl.dsp.exec_cmd([=[hypr-focus-or-spawn orgindex WORK "alacritty -o 'window.dimensions.lines=20' -o 'window.dimensions.columns=100' --class orgindex --title ORGINDEX-WORK -e zsh -c 'cd ~/org/life && vim ~/org/life/work/work.org'"]=]))
end)

hl.bind(mod .. " + SHIFT + D", function()
  hl.dispatch(hl.dsp.exec_cmd([=[hypr-focus-or-spawn orgindex DUMP "alacritty -o 'window.dimensions.lines=20' -o 'window.dimensions.columns=100' --class orgindex --title ORGINDEX-DUMP -e zsh -c 'cd ~/org/life && vim ~/org/life/dump.org'"]=]))
end)

hl.bind(mod .. " + SHIFT + Y", function()
  hl.dispatch(hl.dsp.exec_cmd([=[hypr-focus-or-spawn orgindex YOUTUBE "alacritty -o 'window.dimensions.lines=20' -o 'window.dimensions.columns=100' --class orgindex --title ORGINDEX-YOUTUBE -e zsh -c 'cd ~/org/consume && vim ~/org/consume/youtube/youtube1.org'"]=]))
end)

-- PWA
hl.bind(mod .. " + SHIFT + Z", function()
  hl.dispatch(hl.dsp.exec_cmd([[hypr-focus-or-spawn firefox weekenduo "firefox --new-window 'https://weekenduo.app'"]]))
end)

-- Window management
hl.bind(mod .. " + SHIFT + Q", hl.dsp.window.close())
hl.bind(mod .. " + F", hl.dsp.window.fullscreen())
hl.bind(mod .. " + SUPER + F", hl.dsp.window.fullscreen_state({ internal = 1, client = 1 }))
hl.bind(mod .. " + SHIFT + F", hl.dsp.exec_cmd("hypr-expand-float"))
hl.bind(mod .. " + SHIFT + CTRL + F", function()
  hl.dispatch(hl.dsp.window.set_prop({ prop = "noborder", value = 0 }))
  hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
end)
hl.bind(mod .. " + P", hl.dsp.window.pseudo())
hl.bind(mod .. " + S", hl.dsp.workspace.toggle_special())
hl.bind(mod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special silent" }))
hl.bind(mod .. " + U", hl.dsp.focus({ urgent_or_last = true }))

hl.bind(mod .. " + C", hl.dsp.window.center())
hl.bind(mod .. " + SHIFT + C", hl.dsp.exec_cmd("hyprctl dispatch resizeactive exact \"60% 70%\""))
hl.bind(mod .. " + CTRL + C", function()
  hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
  hl.dispatch(hl.dsp.window.center())
end)

-- Force-move workspaces to their assigned monitors (Reset Layout)
hl.bind(mod .. " + CTRL + A", hl.dsp.exec_cmd(
  'bash -c "for i in {1..10}; do hyprctl dispatch moveworkspacetomonitor \\$i eDP-2; done; for i in {11..20}; do hyprctl dispatch moveworkspacetomonitor \\$i eDP-1; done"'))

-- Workspaces (tags)
for i = 1, 10 do
  local key = i % 10
  hl.bind(mod .. " + " .. key, hl.dsp.focus({ workspace = tostring(i) }))
end
for i = 11, 20 do
  local key = (i - 10) % 10
  hl.bind(mod .. " + CTRL + " .. key, hl.dsp.focus({ workspace = tostring(i) }))
end
for i = 1, 10 do
  local key = i % 10
  hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = tostring(i) }))
end
for i = 1, 10 do
  local key = i % 10
  hl.bind(mod .. " + SUPER + SHIFT + " .. key, hl.dsp.window.move({ workspace = tostring(i) .. " silent" }))
end
for i = 11, 20 do
  local key = (i - 10) % 10
  hl.bind(mod .. " + SHIFT + CTRL + " .. key, hl.dsp.window.move({ workspace = tostring(i) }))
end
for i = 11, 20 do
  local key = (i - 10) % 10
  hl.bind(mod .. " + SUPER + SHIFT + CTRL + " .. key, hl.dsp.window.move({ workspace = tostring(i) .. " silent" }))
end

hl.bind(mod .. " + Escape", hl.dsp.exec_cmd("hypr-previous-workspace"))
hl.bind(mod .. " + V", hl.dsp.focus({ window = "title:^(Picture-in-Picture)$" }))

-- Notifications
hl.bind(mod .. " + N", hl.dsp.exec_cmd("swaync-client -t -sw"))
hl.bind(mod .. " + SHIFT + N", hl.dsp.exec_cmd("swaync-client -C"))
hl.bind(mod .. " + CTRL + N", hl.dsp.exec_cmd("swaync-client -d"))
hl.bind(mod .. " + BackSpace", hl.dsp.exec_cmd("swaync-client --close-latest"))

hl.bind(mod .. " + O", hl.dsp.exec_cmd("hypr-focus-other-monitor"))
hl.bind(mod .. " + CTRL + O", hl.dsp.exec_cmd("hypr-send-to-other-monitor"))

-- Sticky on all workspaces
hl.bind(mod .. " + SHIFT + CTRL + S", hl.dsp.window.pin({ action = "toggle" }))

-- Move focus
hl.bind(mod .. " + J", hl.dsp.window.cycle_next())
hl.bind(mod .. " + K", hl.dsp.window.cycle_next({ next = false }))

-- Change layout orientation / stack
hl.bind(mod .. " + SHIFT + L", hl.dsp.layout("orientationleft"))
hl.bind(mod .. " + SHIFT + H", hl.dsp.layout("orientationright"))
hl.bind(mod .. " + CTRL + Return", hl.dsp.layout("swapwithmaster master"))
hl.bind(mod .. " + CTRL + Space", function()
  hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
  hl.dispatch(hl.dsp.layout("orientationnext"))
end)
hl.bind(mod .. " + SHIFT + Space", hl.dsp.layout("orientationprev"))

hl.bind(mod .. " + F5", _toggle_animations)

-- Toggle Auto-Rotation
hl.bind(mod .. " + SHIFT + R", hl.dsp.exec_cmd("hypr-iio-toggle"))
hl.bind(mod .. " + Space", hl.dsp.exec_cmd("hypr-touch-menu"))

-- Resize helpers (Hyprland 0.55.4: hl.dsp.window.resize broken — uses absolute not incremental)
-- Master layout: adjust mfact via layout toggle
-- Dwindle layout: resizeactive is broken in Lua binding, no workaround
local _mfact = 0.5
local function adjust_mfact(delta)
  _mfact = math.max(0.05, math.min(0.95, _mfact + delta))
  hl.config({ master = { mfact = _mfact }, general = { layout = "dwindle" } })
  hl.config({ general = { layout = "master" } })
end

-- Resize binds (master layout)
hl.bind(mod .. " + H", function() adjust_mfact(-0.02) end, { repeating = true })
hl.bind(mod .. " + L", function() adjust_mfact(0.02) end, { repeating = true })
hl.bind(mod .. " + CTRL + K", hl.dsp.layout("orientationleft"))
hl.bind(mod .. " + CTRL + J", hl.dsp.layout("orientationright"))

-- Mouse drag/resize (bindm equivalent)
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Move window
hl.bind(mod .. " + SHIFT + J", hl.dsp.window.swap({ next = true }))
hl.bind(mod .. " + SHIFT + K", hl.dsp.window.swap({ prev = true }))

-- Floating move (10px steps, repeating)
hl.bind(mod .. " + SHIFT + CTRL + J", hl.dsp.window.move({ x = 0, y = 10, relative = true }), { repeating = true })
hl.bind(mod .. " + SHIFT + CTRL + K", hl.dsp.window.move({ x = 0, y = -10, relative = true }), { repeating = true })
hl.bind(mod .. " + SHIFT + CTRL + H", hl.dsp.window.move({ x = -10, y = 0, relative = true }), { repeating = true })
hl.bind(mod .. " + SHIFT + CTRL + L", hl.dsp.window.move({ x = 10, y = 0, relative = true }), { repeating = true })

-- Screenshot
hl.bind("Print", hl.dsp.exec_cmd('grim -g "$(slurp)" - | wl-copy'))
hl.bind("CTRL + Print", hl.dsp.exec_cmd('grim -g "$(slurp)" - | satty -f -'))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("gnome-screenshot -i"))

-- Zoom (mouse wheel)
hl.bind(mod .. " + mouse_down", hl.dsp.exec_cmd(
  "hyprctl -q keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor -j | jq '.float * 1.1')"))
hl.bind(mod .. " + mouse_up", hl.dsp.exec_cmd(
  "hyprctl -q keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor -j | jq '(.float * 0.9) | if . < 1 then 1 else . end')"))

-- Zoom (keyboard, repeating: binde equivalent)
hl.bind(mod .. " + equal", hl.dsp.exec_cmd(
  "hyprctl -q keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor -j | jq '.float * 1.1')"),
  { repeating = true })
hl.bind(mod .. " + minus", hl.dsp.exec_cmd(
  "hyprctl -q keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor -j | jq '(.float * 0.9) | if . < 1 then 1 else . end')"),
  { repeating = true })
hl.bind(mod .. " + KP_Add", hl.dsp.exec_cmd(
  "hyprctl -q keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor -j | jq '.float * 1.1')"),
  { repeating = true })
hl.bind(mod .. " + KP_Subtract", hl.dsp.exec_cmd(
  "hyprctl -q keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor -j | jq '(.float * 0.9) | if . < 1 then 1 else . end')"),
  { repeating = true })

-- Reset zoom
hl.bind(mod .. " + SHIFT + mouse_up", hl.dsp.exec_cmd("hyprctl -q keyword cursor:zoom_factor 1"))
hl.bind(mod .. " + SHIFT + mouse_down", hl.dsp.exec_cmd("hyprctl -q keyword cursor:zoom_factor 1"))
hl.bind(mod .. " + SHIFT + minus", hl.dsp.exec_cmd("hyprctl -q keyword cursor:zoom_factor 1"))
hl.bind(mod .. " + SHIFT + KP_Subtract", hl.dsp.exec_cmd("hyprctl -q keyword cursor:zoom_factor 1"))
hl.bind(mod .. " + SHIFT + 0", hl.dsp.exec_cmd("hyprctl -q keyword cursor:zoom_factor 1"))

-- Volume and brightness (locked = works when screens locked: bindl equivalent)
for _, entry in ipairs({
  { "XF86AudioRaiseVolume", "change-volume +5" },
  { "XF86AudioLowerVolume", "change-volume -5" },
  { "XF86AudioMute", "pamixer -t && sync-volume" },
  { "XF86AudioMicMute", "pamixer --default-source -t" },
  { "XF86AudioPlay", "playerctl play-pause" },
  { "XF86AudioNext", "playerctl next" },
  { "XF86AudioPrev", "playerctl previous" },
  { "XF86MonBrightnessUp", "brightness-ctl up 5" },
  { "XF86MonBrightnessDown", "brightness-ctl down 5" },
}) do
  hl.bind(entry[1], hl.dsp.exec_cmd(entry[2]), { locked = true })
end

hl.bind(mod .. " + slash", hl.dsp.exec_cmd("hypr-commands"))

-- --- LEADER KEY SUBMAP ---
hl.bind(mod .. " + comma", hl.dsp.submap("leader"))

hl.define_submap("leader", function()
  hl.bind("t", function()
    hl.dispatch(hl.dsp.exec_cmd(terminal))
    hl.dispatch(hl.dsp.submap("reset"))
  end)
  hl.bind("b", function()
    hl.dispatch(hl.dsp.exec_cmd(browser))
    hl.dispatch(hl.dsp.submap("reset"))
  end)
  hl.bind("v", function()
    hl.dispatch(hl.dsp.submap("vim-mode"))
    hl.dispatch(hl.dsp.exec_cmd('notify-send -t 1000 "ENTER VIM MODE"'))
  end)
  hl.bind("r", function()
    hl.dispatch(hl.dsp.exec_cmd("hyprctl reload"))
    hl.dispatch(hl.dsp.submap("reset"))
  end)
  hl.bind("k", function()
    hl.dispatch(hl.dsp.exec_cmd("hypr-ai-agents --menu"))
    hl.dispatch(hl.dsp.submap("reset"))
  end)
  hl.bind("escape", hl.dsp.submap("reset"))
  hl.bind("q", hl.dsp.submap("reset"))
end)

-- --- VIM-MODE SUBMAP ---
hl.define_submap("vim-mode", function()
  hl.bind("h", hl.dsp.exec_cmd("wtype -P Left"), { repeating = true })
  hl.bind("j", hl.dsp.exec_cmd("wtype -P Down"), { repeating = true })
  hl.bind("k", hl.dsp.exec_cmd("wtype -P Up"), { repeating = true })
  hl.bind("l", hl.dsp.exec_cmd("wtype -P Right"), { repeating = true })
  hl.bind("SHIFT + h", hl.dsp.exec_cmd("wtype -M alt -P Left"), { repeating = true })
  hl.bind("SHIFT + l", hl.dsp.exec_cmd("wtype -M alt -P Right"), { repeating = true })
  hl.bind("w", hl.dsp.exec_cmd("wtype -M control -P Right"), { repeating = true })
  hl.bind("b", hl.dsp.exec_cmd("wtype -M control -P Left"), { repeating = true })
  hl.bind("i", function()
    hl.dispatch(hl.dsp.submap("reset"))
    hl.dispatch(hl.dsp.exec_cmd('notify-send -t 1000 "EXIT VIM MODE"'))
  end)
  hl.bind("escape", function()
    hl.dispatch(hl.dsp.submap("reset"))
    hl.dispatch(hl.dsp.exec_cmd('notify-send -t 1000 "EXIT VIM MODE"'))
  end)
end)

-- ================================================================================
-- --- WINDOW RULES ---
-- ================================================================================

-- weekenduo
hl.window_rule({ match = { title = ".*weekenduo.*" }, float = true })
hl.window_rule({ match = { title = ".*weekenduo.*" }, size = { 1000, 650 } })
hl.window_rule({ match = { title = ".*weekenduo.*" }, center = true })

-- orgindex
hl.window_rule({ match = { class = "orgindex" }, float = true })
hl.window_rule({ match = { class = "orgindex" }, size = { 1100, 680 } })
hl.window_rule({ match = { class = "orgindex" }, center = true })

-- JetBrains Toolbox
hl.window_rule({ match = { class = "JetBrains Toolbox" }, float = true })
hl.window_rule({ match = { title = "Event Tester" }, float = true })

-- Firefox PiP
hl.window_rule({ match = { title = "Picture-in-Picture" }, float = true })
hl.window_rule({ match = { title = "Picture-in-Picture" }, pin = true })
hl.window_rule({ match = { title = "Picture-in-Picture" }, size = { "30%", "30%" } })
hl.window_rule({ match = { title = "Picture-in-Picture" }, move = { "65%", "5%" } })

-- Disable gaps/borders when only one window is open
hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
hl.window_rule({ match = { float = false, workspace = "w[tv1]" }, border_size = 0 })
hl.window_rule({ match = { float = false, workspace = "w[tv1]" }, rounding = 0 })

-- Disable gaps/borders when a window is fullscreen/maximized
hl.workspace_rule({ workspace = "f[1]", gaps_out = 0, gaps_in = 0 })
hl.window_rule({ match = { float = false, workspace = "f[1]" }, border_size = 0 })
hl.window_rule({ match = { float = false, workspace = "f[1]" }, rounding = 0 })

-- --- LAYER RULES ---
hl.layer_rule({ match = { namespace = "wvkbd" }, above_lock = 2 })
hl.layer_rule({ match = { namespace = "wvkbd-mobintl" }, above_lock = 2 })

-- ================================================================================
-- --- PLUGIN: TOUCH GESTURES (TODO: fix API for this Hyprland version) ---
-- ================================================================================
-- The plugin config format below is NOT compatible with this version.
-- hl.gesture() supports simple swipe gestures (see example config).
-- Complex edge swipes/taps may need hyprgrass plugin or different API.

-- hl.config({
--   plugin = {
--     touch_gestures = {
--       sensitivity = 4.0,
--       edge_margin = 100,
--
--       workspace_swipe = true,
--       workspace_swipe_cancel_ratio = 0.15,
--
--       -- Edge swipes
--       ["hyprgrass-bind"] = {
--         "edge:u:d, exec, nwg-drawer",
--         "edge:d:u, togglespecialworkspace",
--         "edge:r:l, workspace, +1",
--         "edge:l:r, workspace, -1",
--         "edge:l:u, exec, change-volume +4",
--         "edge:l:d, exec, change-volume -4",
--         "edge:r:u, exec, adjust-sync-brightness +5%",
--         "edge:r:d, exec, adjust-sync-brightness 5%-",
--         -- Taps
--         "tap:3, exec, hypr-touch-action",
--         "tap:4, exec, hypr-touch-menu",
--         "tap:5, exec, hypr-toggle-kb",
--         -- Swipes
--         "swipe:3:d, exec," .. browser,
--         "swipe:4:d, exec, hypr-iio-toggle",
--         "swipe:5:d, exec, hypr-profile",
--         "swipe:5:u, exec, wlogout",
--         -- Long presses (non-mouse)
--         "longpress:5, exec, wlogout",
--       },
--       -- Longpress mouse binds
--       ["hyprgrass-bindm"] = {
--         "longpress:2, movewindow",
--         "longpress:3, resizewindow",
--       },
--     },
--   },
-- })

-- Commented out: hyprexpo plugin
-- hl.config({
--   plugin = {
--     hyprexpo = {
--       columns = 3,
--       gap_size = 5,
--       bg_col = "#111111",
--       workspace_method = "center current",
--       enable_gesture = true,
--       gesture_fingers = 3,
--       gesture_distance = 300,
--       gesture_positive = true,
--     },
--   },
-- })
