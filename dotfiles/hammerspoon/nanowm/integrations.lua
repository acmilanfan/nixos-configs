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

local sketchybarUpdateTimer = hs.timer.delayed.new(0.15, function()
    doUpdateSketchybar()
end)

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
-- Native Canvas Borders Integration
-- =============================================================================

M.borderCanvases = {}

function M.startBorders()
    state.bordersCurrentlyShowing = true
    M.drawBorders()
end

function M.stopBorders()
    state.bordersCurrentlyShowing = false
    for _, canvas in pairs(M.borderCanvases) do
        canvas:hide()
    end
end

function M.toggleBorders()
    state.bordersEnabled = not state.bordersEnabled
    if state.bordersEnabled then
        hs.alert.show("Borders: ON (Native)")
        M.updateBordersVisibility()
    else
        hs.alert.show("Borders: OFF")
        M.stopBorders()
    end
    state.triggerSave()
end

function M.updateBordersVisibility()
    if not state.bordersEnabled then return end

    local shouldHide = state.isFullscreen

    if shouldHide and state.bordersCurrentlyShowing then
        M.stopBorders()
    elseif not shouldHide then
        state.bordersCurrentlyShowing = true
        M.drawBorders()
    end
end

function M.drawBorders()
    if not state.bordersEnabled or not state.bordersCurrentlyShowing then
        M.stopBorders()
        return
    end

    local activeWins = {}
    local focusedWin = hs.window.focusedWindow()
    local focusedId = focusedWin and focusedWin:id() or nil

    -- We need to know which windows to draw borders around.
    -- We can ask core.lua for visible tiled windows on all active tags.
    for i, tag in ipairs(state.activeTags) do
        -- Only draw borders if layout is not mono and count > 1
        local currentLayout = state.getLayout(tag)
        local wins = require("nanowm.core").getTiledWindows(tag)
        if currentLayout ~= "mono" and #wins > 1 then
            for _, win in ipairs(wins) do
                table.insert(activeWins, win)
            end
        end
    end

    -- Add special tag windows if active
    if state.special.active then
        local specialWins = require("nanowm.core").getTiledWindows(state.special.tag)
        local currentLayout = state.getLayout(state.special.tag)
        if currentLayout ~= "mono" and #specialWins > 1 then
            for _, win in ipairs(specialWins) do
                table.insert(activeWins, win)
            end
        end
    end

    -- Create or update canvases per screen
    local screens = hs.screen.allScreens()
    local usedScreens = {}

    for _, s in ipairs(screens) do
        local sid = s:id()
        usedScreens[sid] = true

        if not M.borderCanvases[sid] then
            M.borderCanvases[sid] = hs.canvas.new(s:fullFrame())
            M.borderCanvases[sid]:level(hs.canvas.windowLevels.overlay)
        else
            M.borderCanvases[sid]:frame(s:fullFrame())
        end

        local c = M.borderCanvases[sid]
        c:replaceElements() -- clear

        -- Draw borders for windows on this screen
        local sFrame = s:fullFrame()
        for _, win in ipairs(activeWins) do
            local wf = win:frame()
            -- Check if window is on this screen (rough intersection)
            if wf.x < sFrame.x + sFrame.w and wf.x + wf.w > sFrame.x and
               wf.y < sFrame.y + sFrame.h and wf.y + wf.h > sFrame.y then

                local isFocused = (win:id() == focusedId)
                local color = isFocused and {hex="#734899", alpha=1.0} or {hex="#444444", alpha=0.8}

                -- Convert global coordinates to canvas-local coordinates
                local localFrame = {
                    x = wf.x - sFrame.x,
                    y = wf.y - sFrame.y,
                    w = wf.w,
                    h = wf.h
                }

                c:appendElements({
                    type = "rectangle",
                    action = "stroke",
                    strokeColor = color,
                    strokeWidth = 4,
                    frame = localFrame,
                    roundedRectRadii = {xRadius = 6, yRadius = 6}
                })
            end
        end
        c:show()
    end

    -- Cleanup old canvases for disconnected screens
    for sid, canvas in pairs(M.borderCanvases) do
        if not usedScreens[sid] then
            canvas:delete()
            M.borderCanvases[sid] = nil
        end
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

    print("[NanoWM] Re-triggering driver initialization...")
    -- Run darwin-startup to ensure Karabiner drivers and HID environment is clean
    hs.task.new("/bin/zsh", nil, { "-c", "launchctl kickstart -k gui/$(id -u)/local.darwin-startup" }):start()

    -- Wait a moment for drivers to settle before reloading Kanata
    hs.timer.doAfter(0.8, function()
        print("[NanoWM] Reloading Kanata instances...")
        hs.task.new("/bin/zsh", function(exitCode, _, stdErr)
            if exitCode == 0 then
                print("[NanoWM] Kanata reloaded successfully")
            else
                print("[NanoWM] Kanata reload failed: " .. (stdErr or "unknown error"))
            end
        end, { "-c", "bash " .. script }):start()
    end)
end

function M.setupSystemWatcher()
    if systemWatcher then systemWatcher:stop() end

    systemWatcher = hs.caffeinate.watcher.new(function(event)
        if event == hs.caffeinate.watcher.systemDidWake or
           event == hs.caffeinate.watcher.screensDidUnlock or
           event == hs.caffeinate.watcher.screensDidWake then
            -- Proactively kill karabiner_grabber on wake to prevent it from stealing HID access
            -- This is safe because we have NOPASSWD for killall in sudoers
            hs.task.new("/usr/bin/sudo", nil, { "-n", "/usr/bin/killall", "-9", "karabiner_grabber" }):start()

            -- Force clock update immediately on wake
            hs.task.new("/bin/zsh", nil, { "-c", "sketchybar --trigger clock_tick" }):start()

            -- Always reload Kanata on wake: both instances race to grab the Apple Internal Keyboard
            -- via IOKit exclusive access. The loser stays running (so TCP port checks pass) but
            -- silently drops all keyboard input. The only reliable fix is an unconditional reload.
            hs.timer.doAfter(2.0, function()
                -- Kill karabiner_grabber if it reappeared before reloading
                hs.task.new("/usr/bin/pgrep", function(pgrepExitCode)
                    if pgrepExitCode == 0 then
                        print("[NanoWM] Karabiner grabber detected after wake, killing before reload...")
                        hs.task.new("/usr/bin/sudo", nil, { "-n", "/usr/bin/killall", "-9", "karabiner_grabber" }):start()
                    end
                    print("[NanoWM] Reloading Kanata after wake...")
                    M.reloadKanata()
                end, { "-x", "karabiner_grabber" }):start()
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
end

return M
