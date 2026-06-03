-- =============================================================================
-- NanoWM Integrations
-- Sketchybar, JankyBorders, battery saver, and timer functionality
-- =============================================================================

local state = require("nanowm.state")
local core = require("nanowm.core")

local M = {}

-- =============================================================================
-- Sketchybar Integration
-- =============================================================================

local function doUpdateSketchybar()
    local function isUtilityWindow(win)
        if not win then return false end
        local id = win:id()
        local title = (win:title() or ""):lower()
        return id == state.weekenduoWinId or
               string.find(title, "orgindex", 1, true)
    end

    local managedWins = require("nanowm.watchers").getManagedWindows()

    local tagCounts = {}
    for i = 1, 20 do tagCounts[tostring(i)] = 0 end
    tagCounts["S"] = 0
    tagCounts["special"] = 0

    for _, win in ipairs(managedWins) do
        local id = win:id()
        local winTag = state.tags[id]
        if winTag then
            if not core.isFloating(win) or isUtilityWindow(win) then
                local tStr = tostring(winTag)
                if tagCounts[tStr] ~= nil then
                    tagCounts[tStr] = tagCounts[tStr] + 1
                end
            end
        end
    end

    local activeTagsList = {}
    for _, t in ipairs(state.activeTags) do table.insert(activeTagsList, tostring(t)) end
    local activeTagsStr = table.concat(activeTagsList, " ")

    local tag = state.special.active and "S" or tostring(state.currentTag)
    local currentTagValue = state.special.active and state.special.tag or state.currentTag
    local windowCount = tagCounts[tostring(currentTagValue)] or 0
    local layout = state.getLayout(currentTagValue)
    local isFullscreen = state.isFullscreen and "1" or "0"

    local occupiedTags = {}
    for i = 1, 20 do
        if tagCounts[tostring(i)] > 0 then
            table.insert(occupiedTags, tostring(i))
        end
    end
    if tagCounts["special"] > 0 then
        table.insert(occupiedTags, "S")
    end
    local occupied = table.concat(occupiedTags, " ")

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
    local isFloating = "0"
    local focusedWin = hs.window.focusedWindow()
    if focusedWin then
        if focusedWin:application() then
            focusedApp = focusedWin:application():name() or ""
        end
        isFloating = core.isFloating(focusedWin) and "1" or "0"
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

    local triggerArgs = string.format(
        'TAG="%s" ACTIVE_TAGS="%s" WINDOWS="%d" LAYOUT="%s" FULLSCREEN="%s" TIMER="%s" APP="%s" IS_FLOATING="%s" OCCUPIED="%s" URGENT="%s"',
        tag, activeTagsStr, windowCount, layout, isFullscreen, timerRemaining, focusedApp, isFloating, occupied, urgent
    )

    -- Single shell invocation for both triggers; -c avoids loading the full login profile
    local cmd = string.format(
        'sketchybar --trigger nanowm_update %s 2>/dev/null; sketchybar --trigger nanowm_update_secondary %s 2>/dev/null',
        triggerArgs, triggerArgs
    )
    hs.task.new("/bin/zsh", nil, { "-c", cmd }):start()
end

local sketchybarUpdateTimer = hs.timer.delayed.new(
    require("nanowm.config").perf.battery.sbarDelay, doUpdateSketchybar)

local function rebuildSketchybarTimer()
    sketchybarUpdateTimer:stop()
    sketchybarUpdateTimer = hs.timer.delayed.new(state.perfProfile().sbarDelay, doUpdateSketchybar)
end

function M.updateSketchybar()
    if not state.sketchybarEnabled then return end
    sketchybarUpdateTimer:start()
end

function M.updateSketchybarNow()
    if not state.sketchybarEnabled then return end
    doUpdateSketchybar()
end

function M.toggleSketchybar()
    hs.task.new("/bin/zsh", function(exitCode)
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
-- Battery Saver Mode
-- =============================================================================

function M.toggleBatterySaver()
    state.batterySaverEnabled = not state.batterySaverEnabled

    if state.batterySaverEnabled then
        state.batterySaverPreviousState.sketchybar = state.sketchybarEnabled

        os.execute("pkill -x sketchybar 2>/dev/null")
        state.sketchybarEnabled = false

        hs.alert.show("🔋 Battery Saver: ON\nSketchybar disabled", 2)
    else
        if state.batterySaverPreviousState.sketchybar then
            os.execute("/bin/zsh -l -c 'sketchybar &' &")
            state.sketchybarEnabled = true
            hs.timer.doAfter(1, function()
                M.updateSketchybar()
            end)
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
    if mode ~= "default" and mode ~= "homerow" and mode ~= "split" and mode ~= "angle" and mode ~= "disabled" then
        hs.alert.show("Invalid Kanata mode: " .. tostring(mode))
        return
    end

    local script = os.getenv("HOME") .. "/.config/kanata/switch-kanata.sh"
    hs.alert.show("Switching Kanata to: " .. mode .. "...")

    hs.task.new("/bin/zsh", function(exitCode, _, stdErr)
        if exitCode == 0 then
            state.kanataMode = mode
            state.triggerSave()
            local modeName = "Standard"
            if mode == "homerow" then modeName = "Home Row Mods"
            elseif mode == "split" then modeName = "Split Layout"
            elseif mode == "angle" then modeName = "Angle Mod"
            elseif mode == "disabled" then modeName = "Disabled" end
            hs.alert.show("Kanata: " .. modeName .. " active", 2)
        else
            hs.alert.show("Failed to switch Kanata: " .. stdErr, 5)
            print("Kanata switch error: " .. stdErr)
        end
    end, { "-c", script .. " " .. mode }):start()
end

function M.reloadKanataManual()
    M.reloadKanata(true)
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
local pendingWakeReload = nil
local pendingWakeSketchybar = nil
local wakeReloadRunning = false

function M.reloadKanata(force, callback)
    local script = os.getenv("HOME") .. "/.config/kanata/reload-kanata.sh"
    if not hs.fs.attributes(script) then
        print("[NanoWM] Kanata reload script not found: " .. script)
        if callback then callback(false) end
        return
    end

    print("[NanoWM] Triggering Kanata restart (force=" .. tostring(force) .. ")...")
    local cmd = "bash " .. script
    if force then
        cmd = cmd .. " --force"
    end

    -- Use os.execute with & to truly fire and forget, preventing hs.task from
    -- waiting for backgrounded child processes in the script.
    local ok = os.execute(cmd .. " &")

    if ok then
        print("[NanoWM] Kanata restart triggered successfully (async)")
        if type(callback) == "function" then callback(true) end
    else
        print("[NanoWM] Kanata restart trigger failed to start")
        if type(callback) == "function" then callback(false) end
    end
end

function M.setupSystemWatcher()
    if systemWatcher then systemWatcher:stop() end

    systemWatcher = hs.caffeinate.watcher.new(function(event)
        if event == hs.caffeinate.watcher.systemDidWake or
           event == hs.caffeinate.watcher.screensDidUnlock or
           event == hs.caffeinate.watcher.screensDidWake then

            -- Force clock update immediately on wake
            hs.task.new("/bin/zsh", nil, { "-c", "sketchybar --trigger clock_tick" }):start()

            -- Debounce and Trigger Kanata Reload
            if wakeReloadRunning then return end
            if pendingWakeReload then
                pendingWakeReload:stop()
                pendingWakeReload = nil
            end
            pendingWakeReload = hs.timer.doAfter(0.4, function()
                pendingWakeReload = nil
                if wakeReloadRunning then return end
                wakeReloadRunning = true
                print("[NanoWM] Forcing Kanata reload after wake...")
                M.reloadKanata(true)
                -- Reset the flag after 10 seconds. This ensures only ONE reload
                -- per wake/unlock cycle, even if unlocking is slow.
                hs.timer.doAfter(10.0, function() wakeReloadRunning = false end)
            end)

            -- Refresh sketchybar state after wake. Sketchybar can re-initialize its items
            -- to drawing=off on wake, and the Accessibility API needs time to settle before
            -- allWindows() returns the full window list. 2.5s gives both enough time.
            if pendingWakeSketchybar then
                pendingWakeSketchybar:stop()
                pendingWakeSketchybar = nil
            end
            pendingWakeSketchybar = hs.timer.doAfter(2.5, function()
                pendingWakeSketchybar = nil
                M.updateSketchybar()
            end)
        end
    end)
    systemWatcher:start()
end

-- =============================================================================
-- Edge Trigger (Gesture Proxy)
-- =============================================================================

-- Poll mouse position at 100ms intervals instead of tapping every mouseMoved
-- event, which fires thousands of times/sec and stresses the Hammerspoon event loop.
local edgeTriggerTimer = nil
local lastTriggerTime = 0

function M.setupEdgeTrigger()
    if edgeTriggerTimer then edgeTriggerTimer:stop() end

    edgeTriggerTimer = hs.timer.new(state.perfProfile().edgePoll, function()
        local now = hs.timer.secondsSinceEpoch()
        if now - lastTriggerTime < 1 then return end

        local screen = hs.screen.mainScreen()
        if not screen then return end
        local frame = screen:fullFrame()
        local pos = hs.mouse.absolutePosition()

        if pos.x <= (frame.x + 2) and pos.y <= (frame.y + 2) then
            lastTriggerTime = now
            require("nanowm").toggleOverview()
        end
    end)
    edgeTriggerTimer:start()
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

    -- Restart sketchybar if needed, or kill it if it should be hidden
    hs.task.new("/bin/zsh", function(exitCode)
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

    -- Setup gesture proxy (edge trigger)
    M.setupEdgeTrigger()

    -- Battery/AC watcher: switch performance profile when power source changes
    M.setupBatteryWatcher()
end

-- =============================================================================
-- Battery / AC Performance Profile
-- =============================================================================

local batteryWatcher = nil

function M.onPowerChange()
    local isAC = hs.battery.powerSource() == "AC Power"
    if isAC == state.acPower then return end  -- no change
    state.acPower = isAC
    print("[NanoWM] Power source changed: " .. (isAC and "AC" or "Battery")
          .. " — applying perf profile")
    -- Rebuild timers that have fixed intervals
    rebuildSketchybarTimer()
    M.setupEdgeTrigger()
    require("nanowm.layout").rebuildTileTimer()
end

function M.setupBatteryWatcher()
    if batteryWatcher then batteryWatcher:stop() end
    batteryWatcher = hs.battery.watcher.new(M.onPowerChange)
    batteryWatcher:start()
end

return M
