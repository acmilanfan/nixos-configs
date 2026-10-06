-- =============================================================================
-- Hammerspoon Configuration
-- =============================================================================
-- Emergency Rescue: CMD+ALT+CTRL+0 unhides all windows
-- Emergency Kanata Restart: CMD+ALT+CTRL+K restarts kanata via launchd
-- =============================================================================

-- `open -g hammerspoon://reload` reloads the config. Used by the nix activation
-- (home-darwin.nix) after a rebuild changed any Hammerspoon file: unlike the `hs`
-- CLI it doesn't depend on the IPC port answering. Deferred so the URL event
-- handler returns before the Lua state is torn down.
hs.urlevent.bind("reload", function() hs.timer.doAfter(0.1, hs.reload) end)

hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "0", function()
    hs.alert.show("🚨 Emergency Rescue Initiated 🚨")
    local wins = hs.window.allWindows()
    local screen = hs.screen.mainScreen():frame()
    for _, win in ipairs(wins) do
        win:setFrame({
            x = screen.x + 50,
            y = screen.y + 50,
            w = screen.w - 100,
            h = screen.h - 100,
        })
        win:raise()
    end
end)

-- Emergency kanata restart (Cmd+Alt+Ctrl+K).
-- Works even when kanata is unresponsive because Hammerspoon's event tap
-- is independent of kanata. Launchd KeepAlive restarts kanata within ~1s.
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "k", function()
    hs.execute("sudo /usr/bin/pkill -x kanata 2>/dev/null; true")
    hs.alert("Kanata restarting...")
end)

-- =============================================================================
-- External Modules
-- =============================================================================

-- Required for the `hs` CLI tool
pcall(require, "hs.ipc")

-- Aurora Sweep Browser Remapper
pcall(require, "sweep-remapper")

-- macOS Vim Navigation
local ok, err = pcall(require, "macos-vim-navigation/init")
if not ok then hs.notify.new({ title = "Hammerspoon", informativeText = "macos-vim-navigation: " .. tostring(err) }):send() end

-- Hold Control+Option (alone) to zoom; replaces macOS's modifier-only temporary zoom
local zok, zerr = pcall(require, "zoom-hold")
if not zok then hs.notify.new({ title = "Hammerspoon", informativeText = "zoom-hold: " .. tostring(zerr) }):send() end

-- AClock Spoon
local clock = hs.loadSpoon("AClock")

-- VimMode Spoon
local VimMode = hs.loadSpoon("VimMode")
if VimMode then
    local vimMode = VimMode:new()
    vimMode:shouldShowAlertInNormalMode(false)
    vimMode:disableForApp('Alacritty')
    vimMode:disableForApp('Ghostty')
    vimMode:bindHotKeys({ enter = { { "alt" }, "e" } })
    _G.vim = vimMode  -- used by nanowm's Leader+v
end

-- =============================================================================
-- SketchyBar Event Timers
-- =============================================================================

-- Store timers in a global table to prevent garbage collection
_G.sketchybarTimers = _G.sketchybarTimers or {}

-- Precision clock trigger at the start of every minute
local user = os.getenv("USER") or ""
local sketchybarBin = "/etc/profiles/per-user/" .. user .. "/bin/sketchybar"

local function triggerClockTick()
    hs.task.new(sketchybarBin, nil, { "--trigger", "clock_tick" }):start()
end

-- Initial trigger on config load
triggerClockTick()

-- Self-rescheduling function that always aligns to the next actual minute boundary
local function scheduleNextTick()
    local secondsUntilNextMinute = 60 - os.date("*t").sec
    if secondsUntilNextMinute <= 0 then secondsUntilNextMinute = 60 end
    if _G.sketchybarTimers.next then _G.sketchybarTimers.next:stop() end
    _G.sketchybarTimers.next = hs.timer.doAfter(secondsUntilNextMinute, function()
        triggerClockTick()
        scheduleNextTick()
    end)
end

scheduleNextTick()

-- =============================================================================
-- NanoWM - Tiling Window Manager
-- =============================================================================

local NanoWM
local nmOk, nmResult = pcall(require, "nanowm")
if nmOk then
    NanoWM = nmResult
    local initOk, initErr = pcall(function() NanoWM.init() end)
    if not initOk then hs.notify.new({ title = "Hammerspoon", informativeText = "NanoWM.init: " .. tostring(initErr) }):send() end
else
    hs.notify.new({ title = "Hammerspoon", informativeText = "nanowm load failed: " .. tostring(nmResult) }):send()
end

-- Export NanoWM globally for console access and compatibility
_G.NanoWM = NanoWM

-- =============================================================================
-- AClock Toggle
-- =============================================================================

hs.hotkey.bind({ "cmd", "alt" }, "t", function()
    if clock then
        if clock.toggleShow then
            clock:toggleShow()
        elseif clock.show and clock.hide then
            if clock.canvas and clock.canvas:isShowing() then
                clock:hide()
            else
                clock:show()
            end
        else
            hs.alert.show("AClock method not found")
        end
    else
        hs.alert.show("AClock not loaded")
    end
end)

-- =============================================================================
-- Language Switcher (Universal: Ctrl+Shift+Space)
-- =============================================================================

local function cycleInputSource()
    local current = hs.keycodes.currentSourceID()
    local all_layouts = hs.keycodes.layouts(true) or {}
    local all_methods = hs.keycodes.methods(true) or {}

    local sources = {}
    local seen = {}
    local function add_source(s)
        if s and not seen[s] and not s:find("CharacterPalette") and not s:find("InkInput") then
            table.insert(sources, s)
            seen[s] = true
        end
    end

    for _, s in ipairs(all_layouts) do add_source(s) end
    for _, s in ipairs(all_methods) do add_source(s) end

    if #sources <= 1 then
        hs.alert.show("Only one input source available", 0.5)
        return
    end

    local nextIndex = 1
    for i, source in ipairs(sources) do
        if source == current then
            nextIndex = (i % #sources) + 1
            break
        end
    end

    local nextSource = sources[nextIndex]
    if nextSource then
        hs.keycodes.currentSourceID(nextSource)
        -- Show a cleaner name (e.g., "US" instead of "com.apple.keylayout.US")
        local cleanName = nextSource:match("[^.]*$")
        hs.alert.show("Input: " .. cleanName, 0.5)
    end
end

hs.hotkey.bind({ "ctrl", "shift" }, "space", cycleInputSource)

-- =============================================================================
-- Caps Lock Watcher for SketchyBar
-- =============================================================================

local lastCapsLockState = hs.hid.capslock.get()

local function updateCapsLock(force)
    local currentState = hs.hid.capslock.get()
    if force or currentState ~= lastCapsLockState then
        lastCapsLockState = currentState
        local stateStr = currentState and "on" or "off"
            hs.task.new(sketchybarBin, nil, { "--trigger", "caps_lock_update", "STATE=" .. stateStr }):start()
    end
end

-- Cleanup existing tap on reload
if _G.capsLockTap then
    _G.capsLockTap:stop()
end

-- Watch for flagsChanged (modifier keys like Caps Lock, Shift, Cmd, etc.).
-- Debounced to 100ms: caps-lock state changes are slow human actions and this
-- fires on every Shift/Ctrl/Cmd press otherwise, causing unnecessary HID calls.
-- A debounce (check 100ms after the last modifier event) rather than a throttle:
-- the throttle dropped events, so Shift then Caps Lock within 100ms left the
-- indicator wrong until the next modifier press. Held in _G so it isn't GC'd.
if _G.capsLockCheck then _G.capsLockCheck:stop() end
_G.capsLockCheck = hs.timer.delayed.new(0.1, function() updateCapsLock() end)
_G.capsLockTap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(_)
    _G.capsLockCheck:start()
    return false
end):start()

-- Initial sync
updateCapsLock(true)
