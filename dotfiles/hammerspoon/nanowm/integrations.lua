-- =============================================================================
-- NanoWM Integrations
-- Sketchybar, JankyBorders, battery saver, and timer functionality
-- =============================================================================

local config = require("nanowm.config")
local state = require("nanowm.state")
local core = require("nanowm.core")

local M = {}

-- =============================================================================
-- Sketchybar Integration
-- =============================================================================

local sketchybarUpdateTimer = nil

local function doUpdateSketchybar()
    local tag = state.special.active and "S" or tostring(state.currentTag)
    local windowCount = #core.getTiledWindows(state.special.active and state.special.tag or state.currentTag)
    local layout = state.layout
    local isFullscreen = state.isFullscreen and "1" or "0"

    -- Get occupied tags
    local occupiedTags = {}
    for i = 1, 10 do
        local wins = core.getTiledWindows(i)
        if #wins > 0 then
            table.insert(occupiedTags, tostring(i))
        end
    end
    local specialWins = core.getTiledWindows("special")
    if #specialWins > 0 then
        table.insert(occupiedTags, "S")
    end
    local occupied = table.concat(occupiedTags, " ")

    -- Timer info
    local timerRemaining = ""
    if state.timerEndTime then
        local remaining = state.timerEndTime - os.time()
        if remaining > 0 then
            local mins = math.floor(remaining / 60)
            local secs = remaining % 60
            timerRemaining = string.format("%d:%02d", mins, secs)
        end
    end

    -- Focused app
    local focusedApp = ""
    local focusedWin = hs.window.focusedWindow()
    if focusedWin and focusedWin:application() then
        focusedApp = focusedWin:application():name() or ""
    end

    -- Urgent tags
    local urgentList = {}
    for urgentTag, _ in pairs(state.urgentTags) do
        if urgentTag == "special" then
            table.insert(urgentList, "S")
        else
            table.insert(urgentList, tostring(urgentTag))
        end
    end
    local urgent = table.concat(urgentList, " ")

    local cmd = string.format(
        'sketchybar --trigger nanowm_update TAG="%s" WINDOWS="%d" LAYOUT="%s" FULLSCREEN="%s" TIMER="%s" APP="%s" OCCUPIED="%s" URGENT="%s" 2>/dev/null',
        tag, windowCount, layout, isFullscreen, timerRemaining, focusedApp, occupied, urgent
    )
    hs.task.new("/bin/zsh", nil, { "-c", cmd }):start()
end

function M.updateSketchybar()
    if not state.sketchybarEnabled then return end

    if sketchybarUpdateTimer then
        sketchybarUpdateTimer:stop()
    end

    sketchybarUpdateTimer = hs.timer.doAfter(0.02, function()
        doUpdateSketchybar()
    end)
end

function M.updateSketchybarNow()
    if not state.sketchybarEnabled then return end
    doUpdateSketchybar()
end

function M.toggleSketchybar()
    hs.task.new("/bin/zsh", function(exitCode, stdOut, stdErr)
        if exitCode ~= 0 then
            os.execute("/bin/zsh -l -c 'sketchybar &' &")
            state.sketchybarEnabled = true
            state.triggerSave()
            hs.alert.show("Sketchybar: ON (started)")
            hs.timer.doAfter(1, function()
                M.updateSketchybar()
            end)
            require("nanowm.layout").tile()
        else
            state.sketchybarEnabled = not state.sketchybarEnabled
            state.triggerSave()
            local hiddenVal = state.sketchybarEnabled and "false" or "true"

            hs.task.new("/bin/zsh", function()
                hs.alert.show("Sketchybar: " .. (state.sketchybarEnabled and "ON" or "OFF"))
                if state.sketchybarEnabled then
                    M.updateSketchybar()
                end
                require("nanowm.layout").tile()
            end, { "-c", "sketchybar --bar hidden=" .. hiddenVal }):start()
        end
    end, { "-c", "pgrep -x sketchybar" }):start()
end

-- =============================================================================
-- JankyBorders Integration
-- =============================================================================

function M.startBorders()
    os.execute("/bin/zsh -l -c '$HOME/.config/borders/bordersrc &' &")
end

function M.stopBorders()
    os.execute("pkill -x borders 2>/dev/null")
end

function M.toggleBorders()
    state.bordersEnabled = not state.bordersEnabled
    if state.bordersEnabled then
        hs.alert.show("Borders: ON (smart mode)")
        M.updateBordersVisibility()
    else
        hs.alert.show("Borders: OFF")
        M.stopBorders()
        state.bordersCurrentlyShowing = false
    end
    state.triggerSave()
end

function M.updateBordersVisibility()
    if not state.bordersEnabled then return end

    local tag = state.special.active and state.special.tag or state.currentTag
    local windows = core.getTiledWindows(tag)
    local windowCount = #windows

    local shouldHide = (state.layout == "monocle") or state.isFullscreen or (windowCount <= 1)

    if shouldHide and state.bordersCurrentlyShowing then
        M.stopBorders()
        state.bordersCurrentlyShowing = false
    elseif not shouldHide and not state.bordersCurrentlyShowing then
        M.startBorders()
        state.bordersCurrentlyShowing = true
    end
end

-- =============================================================================
-- Battery Saver Mode
-- =============================================================================

function M.toggleBatterySaver()
    state.batterySaverEnabled = not state.batterySaverEnabled

    if state.batterySaverEnabled then
        state.batterySaverPreviousState.sketchybar = state.sketchybarEnabled
        state.batterySaverPreviousState.borders = state.bordersEnabled

        os.execute("pkill -x sketchybar 2>/dev/null")
        state.sketchybarEnabled = false

        M.stopBorders()
        state.bordersEnabled = false
        state.bordersCurrentlyShowing = false

        hs.alert.show("🔋 Battery Saver: ON\nSketchybar & Borders disabled", 2)
    else
        if state.batterySaverPreviousState.sketchybar then
            os.execute("/bin/zsh -l -c 'sketchybar &' &")
            state.sketchybarEnabled = true
            hs.timer.doAfter(1, function()
                M.updateSketchybar()
            end)
        end

        if state.batterySaverPreviousState.borders then
            state.bordersEnabled = true
            M.updateBordersVisibility()
        end

        hs.alert.show("⚡ Battery Saver: OFF\nFeatures restored", 2)
    end

    state.triggerSave()
end

-- =============================================================================
-- Timer Functions
-- =============================================================================

local sketchybarTimer = hs.timer.new(1, function()
    if state.timerEndTime and state.sketchybarEnabled then
        M.updateSketchybar()
    end
end)

function M.startTimer(minutes)
    if state.activeTimer then
        state.activeTimer:stop()
    end

    state.timerDuration = minutes
    state.timerEndTime = os.time() + (minutes * 60)

    hs.alert.show("Timer started: " .. minutes .. " min")

    state.activeTimer = hs.timer.doAfter(minutes * 60, function()
        hs.alert.show("⏰ Timer finished! (" .. minutes .. " min)", 5)
        hs.sound.getByName("Glass"):play()
        state.activeTimer = nil
        state.timerEndTime = nil
        state.timerDuration = nil
        M.updateSketchybar()
        sketchybarTimer:stop()
    end)

    M.updateSketchybar()
    sketchybarTimer:start()
end

function M.showTimerRemaining()
    if not state.timerEndTime then
        hs.alert.show("No active timer")
        return
    end

    local remaining = state.timerEndTime - os.time()
    if remaining <= 0 then
        hs.alert.show("Timer finished!")
        return
    end

    local mins = math.floor(remaining / 60)
    local secs = remaining % 60
    hs.alert.show(string.format("⏱ Timer: %d:%02d remaining", mins, secs), 2)
end

function M.cancelTimer()
    if state.activeTimer then
        state.activeTimer:stop()
        state.activeTimer = nil
        state.timerEndTime = nil
        state.timerDuration = nil
        hs.alert.show("Timer cancelled")
        M.updateSketchybar()
        sketchybarTimer:stop()
    else
        hs.alert.show("No active timer")
    end
end

-- =============================================================================
-- Kanata Integration
-- =============================================================================

function M.switchKanata(mode)
    if mode ~= "default" and mode ~= "homerow" and mode ~= "split" and mode ~= "angle" then
        hs.alert.show("Invalid Kanata mode: " .. tostring(mode))
        return
    end

    local script = os.getenv("HOME") .. "/.config/kanata/switch-kanata.sh"
    hs.alert.show("Switching Kanata to: " .. mode .. "...")

    hs.task.new("/bin/zsh", function(exitCode, stdOut, stdErr)
        if exitCode == 0 then
            state.kanataMode = mode
            state.triggerSave()
            local modeName = "Standard"
            if mode == "homerow" then modeName = "Home Row Mods"
            elseif mode == "split" then modeName = "Split Layout"
            elseif mode == "angle" then modeName = "Angle Mod" end
            hs.alert.show("Kanata: " .. modeName .. " active", 2)
        else
            hs.alert.show("Failed to switch Kanata: " .. stdErr, 5)
            print("Kanata switch error: " .. stdErr)
        end
    end, { "-c", script .. " " .. mode }):start()
end

function M.toggleKanata()
    local nextMode = (state.kanataMode == "homerow") and "default" or "homerow"
    M.switchKanata(nextMode)
end

function M.startCustomTimer()
    local button, minutes = hs.dialog.textPrompt("Start Timer", "Enter minutes:", "", "Start", "Cancel")
    if button == "Start" then
        local min = tonumber(minutes)
        if min and min > 0 then
            M.startTimer(min)
        else
            hs.alert.show("Invalid number")
        end
    end
end

-- =============================================================================
-- System Watcher (Wake/Unlock)
-- =============================================================================

local systemWatcher = nil

function M.reloadKanata()
    local script = os.getenv("HOME") .. "/.config/kanata/reload-kanata.sh"
    if not hs.fs.attributes(script) then
        print("[NanoWM] Kanata reload script not found: " .. script)
        return
    end

    print("[NanoWM] System event detected, reloading Kanata...")
    hs.task.new("/bin/zsh", function(exitCode, stdOut, stdErr)
        if exitCode == 0 then
            print("[NanoWM] Kanata reloaded successfully")
        else
            print("[NanoWM] Kanata reload failed: " .. (stdErr or "unknown error"))
        end
    end, { "-c", "bash " .. script }):start()
end

function M.setupSystemWatcher()
    if systemWatcher then systemWatcher:stop() end

    systemWatcher = hs.caffeinate.watcher.new(function(event)
        if event == hs.caffeinate.watcher.systemDidWake or
           event == hs.caffeinate.watcher.screensDidUnlock or
           event == hs.caffeinate.watcher.screensDidWake then
            -- Force clock update immediately on wake
            hs.task.new("/bin/zsh", nil, { "-c", "sketchybar --trigger clock_tick" }):start()

            -- With LaunchDaemons, Kanata should handle wake naturally, but often loses HID access.
            -- Force reload to ensure keyboard is functional.
            hs.timer.doAfter(2, function()
                M.reloadKanata()
            end)
        end
    end)
    systemWatcher:start()
end

-- =============================================================================
-- Initialization
-- =============================================================================

-- Track init timers to cancel on rapid reloads
local initTimers = {}

local function cancelInitTimers()
    for _, t in ipairs(initTimers) do t:stop() end
    initTimers = {}
end

local function scheduleInit(delay, fn)
    local t = hs.timer.doAfter(delay, fn)
    table.insert(initTimers, t)
    return t
end

function M.init()
    -- Cancel any outstanding init timers from a previous reload
    cancelInitTimers()

    -- Setup system watcher for wake/unlock events
    M.setupSystemWatcher()

    -- Restore borders state
    if state.bordersEnabled then
        scheduleInit(2, function()
            M.updateBordersVisibility()
        end)
    end

    -- Restart sketchybar if needed, or kill it if it should be hidden
    hs.task.new("/bin/zsh", function(exitCode, stdOut, stdErr)
        if exitCode == 0 then
            -- It's running. Check if it's supposed to be.
            if state.sketchybarEnabled then
                -- Refresh it to ensure everything is correct
                os.execute("pkill -x sketchybar")
                scheduleInit(0.5, function()
                    os.execute("/bin/zsh -l -c 'sketchybar &' &")
                    scheduleInit(2, function()
                        M.updateSketchybar()
                        scheduleInit(0.5, function()
                            M.updateSketchybar()
                        end)
                    end)
                end)
            else
                -- We want it hidden/off. Just kill it.
                os.execute("pkill -x sketchybar")
            end
        else
            -- It's NOT running. Check if it's supposed to be.
            if state.sketchybarEnabled then
                os.execute("/bin/zsh -l -c 'sketchybar &' &")
                scheduleInit(2, function()
                    M.updateSketchybar()
                    scheduleInit(0.5, function()
                        M.updateSketchybar()
                    end)
                end)
            end
        end
    end, { "-c", "pgrep -x sketchybar" }):start()
end

return M
