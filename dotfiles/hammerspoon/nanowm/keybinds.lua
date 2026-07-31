-- =============================================================================
-- NanoWM Key Bindings
-- All hotkey definitions in one place
-- =============================================================================

local config = require("nanowm.config")
local state = require("nanowm.state")
local core = require("nanowm.core")
local layout = require("nanowm.layout")
local actions = require("nanowm.actions")
local tags = require("nanowm.tags")
local menus = require("nanowm.menus")
local integrations = require("nanowm.integrations")
local agents = require("nanowm.agents")
local pass   = require("nanowm.pass")

local M = {}

-- Weekenduo launch watcher, held at module level so a failed launch can't leak it.
-- The filter carries an AXObserver on Firefox; previously it was created per attempt and
-- only unsubscribed inside the success callback, so every launch that never produced a
-- matching window (failed launch, slow Firefox, title mismatch) leaked one observer for
-- the life of the session. The whole AX design here exists to keep observer count minimal.
local weekenduoFilter = nil
local weekenduoTimeout = nil

local function weekenduoCleanup()
    if weekenduoFilter then
        weekenduoFilter:unsubscribe()
        weekenduoFilter = nil
    end
    if weekenduoTimeout then
        weekenduoTimeout:stop()
        weekenduoTimeout = nil
    end
end

-- Modifier shortcuts
local alt = config.modifiers.alt
local altShift = config.modifiers.altShift
local ctrlAlt = config.modifiers.ctrlAlt
local ctrlAltShift = config.modifiers.ctrlAltShift
local cmdAlt = config.modifiers.cmdAlt
local cmdAltShift = config.modifiers.cmdAltShift
local cmdAltShiftCtrl = config.modifiers.cmdAltShiftCtrl

-- =============================================================================
-- Setup Function
-- =============================================================================

function M.setup()
    local home = config.home()

    -- =========================================================================
    -- MENUS
    -- =========================================================================
    hs.hotkey.bind(alt, "m", menus.triggerMenuPalette)
    hs.hotkey.bind(alt, "p", function() menus.openMenu("commands") end)
    hs.hotkey.bind(alt, "i", function() menus.openMenu("windows") end)
    hs.hotkey.bind(alt, "n", menus.openControlMenu)
    hs.hotkey.bind(alt, "/", menus.showKeybindMenu)
    hs.hotkey.bind(altShift, "p", pass.showChooser)

    -- AI Agents: chooser (Alt+A) and SketchyBar popup toggle (Ctrl+Alt+A)
    hs.hotkey.bind(alt,     "a", agents.showMenu)
    hs.hotkey.bind(ctrlAlt, "a", function()
        hs.task.new("/bin/zsh", nil, { "-c", "sketchybar --set ai_agents popup.drawing=toggle 2>/dev/null" }):start()
    end)

    -- Forward Cmd+Shift+/ to app (Help menu)
    hs.hotkey.bind(altShift, "/", function()
        hs.eventtap.keyStroke({ "cmd", "shift" }, "/")
    end)

    -- =========================================================================
    -- NAVIGATION
    -- =========================================================================
    hs.hotkey.bind(alt, "j", function() actions.cycleFocus(1) end)
    hs.hotkey.bind(alt, "k", function() actions.cycleFocus(-1) end)
    hs.hotkey.bind(alt, "tab", function() NanoWM.toggleOverview() end)
    hs.hotkey.bind(alt, "v", actions.focusPip)

    hs.hotkey.bind(alt, "h", function() actions.adjustTiledSize("narrower") end)
    hs.hotkey.bind(alt, "l", function() actions.adjustTiledSize("wider") end)

    -- =========================================================================
    -- TAGS
    -- =========================================================================
    for i = 1, 9 do
        hs.hotkey.bind(alt, tostring(i), function() tags.gotoTag(i) end)
        hs.hotkey.bind(altShift, tostring(i), function() tags.moveWindowToTag(i) end)
        hs.hotkey.bind(ctrlAlt, tostring(i), function() tags.gotoTag(10 + i) end)
        hs.hotkey.bind(ctrlAltShift, tostring(i), function() tags.moveWindowToTag(10 + i) end)
    end
    hs.hotkey.bind(alt, "0", function() tags.gotoTag(10) end)
    hs.hotkey.bind(altShift, "0", function() tags.moveWindowToTag(10) end)
    hs.hotkey.bind(ctrlAlt, "0", function() tags.gotoTag(20) end)
    hs.hotkey.bind(ctrlAltShift, "0", function() tags.moveWindowToTag(20) end)

    hs.hotkey.bind(alt, "o", function() tags.focusNextMonitor() end)
    hs.hotkey.bind(ctrlAlt, "o", function() tags.moveWindowToNextMonitor() end)

    hs.hotkey.bind(alt, "escape", tags.togglePrevTag)
    hs.hotkey.bind(alt, "s", tags.toggleSpecial)
    hs.hotkey.bind(altShift, "s", function()
        tags.moveWindowToTag(state.special.tag)
        hs.alert.show("Moved to Special")
    end)
    hs.hotkey.bind(alt, "u", tags.gotoUrgent)
    hs.hotkey.bind(altShift, "u", tags.undoLastMove)

    -- Sync Dashboard
    hs.hotkey.bind(ctrlAlt, "u", function()
        core.launchSyncMon()
    end)

    -- Tag memory
    hs.hotkey.bind(altShift, "m", tags.saveCurrentWindowTag)
    hs.hotkey.bind(ctrlAltShift, "m", tags.saveAllWindowTags)

    -- =========================================================================
    -- WINDOW MANAGEMENT
    -- =========================================================================
    hs.hotkey.bind({ "cmd" }, "space", actions.toggleLayout)
    hs.hotkey.bind(alt, "f", actions.toggleFullscreen)
    hs.hotkey.bind(alt, "c", actions.centerWindow)
    hs.hotkey.bind(altShift, "c", actions.resizeFloatingTo60)
    hs.hotkey.bind(alt, "g", actions.toggleGaps)
    hs.hotkey.bind(ctrlAltShift, "s", actions.toggleSticky)
    hs.hotkey.bind(altShift, "space", actions.toggleFloat)
    hs.hotkey.bind(altShift, "q", actions.closeWindow)
    hs.hotkey.bind(ctrlAlt, "f", tags.toggleFreeMode)

    hs.hotkey.bind(alt, "r", actions.cycleWindowSize)

    -- Combined swap/resize keybinds (context-aware)
    hs.hotkey.bind(altShift, "h", function()
        local win = hs.window.focusedWindow()
        if win and core.isFloating(win) then
            actions.resizeFloatingWindow("narrower")
        else
            actions.swapWindow(-1)
        end
    end)

    hs.hotkey.bind(altShift, "l", function()
        local win = hs.window.focusedWindow()
        if win and core.isFloating(win) then
            actions.resizeFloatingWindow("wider")
        else
            actions.swapWindow(1)
        end
    end)

    hs.hotkey.bind(altShift, "k", function()
        local win = hs.window.focusedWindow()
        if win and core.isFloating(win) then
            actions.resizeFloatingWindow("shorter")
        else
            actions.swapWindow(-1)
        end
    end)

    hs.hotkey.bind(altShift, "j", function()
        local win = hs.window.focusedWindow()
        if win and core.isFloating(win) then
            actions.resizeFloatingWindow("taller")
        else
            actions.swapWindow(1)
        end
    end)

    -- Floating window movement
    hs.hotkey.bind(ctrlAlt, "h", function() actions.moveFloatingWindow("left") end)
    hs.hotkey.bind(ctrlAlt, "l", function() actions.moveFloatingWindow("right") end)
    hs.hotkey.bind(ctrlAlt, "k", function() actions.moveFloatingWindow("up") end)
    hs.hotkey.bind(ctrlAlt, "j", function() actions.moveFloatingWindow("down") end)

    -- =========================================================================
    -- APPLICATIONS
    -- =========================================================================
    hs.hotkey.bind(alt, "return", function()
        core.launchTask("/usr/bin/open", { "-n", "-a", "Alacritty" })
    end)
    hs.hotkey.bind(alt, "b", function()
        core.launchTask("/usr/bin/open", { "-n", "-a", "Firefox" })
    end)
    hs.hotkey.bind(altShift, "b", function()
        hs.application.launchOrFocus("Firefox")
    end)
    hs.hotkey.bind(alt, "d", function()
        hs.application.launchOrFocus("Raycast")
    end)
    hs.hotkey.bind(altShift, "v", function()
        hs.task.new("/usr/bin/open", nil, { "raycast://extensions/raycast/clipboard-history/clipboard-history" }):start()
    end)

    -- =========================================================================
    -- APP WINDOWS (Focus or Create)
    -- =========================================================================
    local function focusOrCreateApp(titlePattern, launchCmd, sizeFactor, appName)
        local allWins = require("nanowm.watchers").getManagedWindows()
        local targetWin = nil
        local lowerPattern = titlePattern:lower()

        for _, win in ipairs(allWins) do
            local title = (win:title() or ""):lower()
            local app = win:application()
            local winAppName = app and app:name() or ""

            if (not appName or winAppName == appName) and string.find(title, lowerPattern, 1, true) then
                targetWin = win
                break
            end
        end

        if targetWin then
            actions.bringWindowToCurrentContext(targetWin, sizeFactor)
            return
        end

        -- Poll for the window to appear and resize it immediately when found.
        if sizeFactor then
            local lowerPattern = titlePattern:lower()
            local attempts = 0
            local function poll()
                attempts = attempts + 1
                if attempts > 20 then return end
                for _, app in ipairs(hs.application.runningApplications()) do
                    if app:name() == appName then
                        for _, w in ipairs(app:allWindows()) do
                            local wid = w:id()
                            if wid and wid > 0 then
                                local title = w:title() or ""
                                if title:lower():find(lowerPattern, 1, true) then
                                    state.floatingOverrides[wid] = true
                                    state.lastIntendedFocusId = wid
                                    local screen = hs.screen.mainScreen():frame()
                                    local newW = math.floor(screen.w * sizeFactor)
                                    local newH = math.floor(screen.h * sizeFactor)
                                    local newX = math.floor(screen.x + (screen.w - newW) / 2)
                                    local newY = math.floor(screen.y + (screen.h - newH) / 2)
                                    w:setFrame({ x = newX, y = newY, w = newW, h = newH })
                                    w:raise()
                                    w:focus()
                                    return
                                end
                            end
                        end
                    end
                end
                hs.timer.doAfter(0.2, poll)
            end
            poll()
        end

        core.launchTask("/bin/zsh", { "-c", launchCmd })
    end

    hs.hotkey.bind(altShift, "o", function()
        focusOrCreateApp(
            "ORGINDEX-AGENDA",
            string.format('open -n -a Alacritty --args -o "window.dimensions.lines=20" -o "window.dimensions.columns=100" --title "ORGINDEX-AGENDA" -e zsh -c "nvim --cmd \\"cd %s/org/life\\" -c \\"lua require(\\\\\\"orgmode.api.agenda\\\\\\").agenda({span = 1})\\""', home),
            0.6,
            "Alacritty"
        )
    end)

    hs.hotkey.bind(altShift, "w", function()
        focusOrCreateApp(
            "ORGINDEX-WORK",
            string.format('open -n -a Alacritty --args -o "window.dimensions.lines=20" -o "window.dimensions.columns=100" --title "ORGINDEX-WORK" -e zsh -c "cd %s/org/life && vim %s/org/life/work/work.org"', home, home),
            0.6,
            "Alacritty"
        )
    end)

    hs.hotkey.bind(altShift, "d", function()
        focusOrCreateApp(
            "ORGINDEX-DUMP",
            string.format('open -n -a Alacritty --args -o "window.dimensions.lines=20" -o "window.dimensions.columns=100" --title "ORGINDEX-DUMP" -e zsh -c "cd %s/org/life && vim %s/org/life/dump.org"', home, home),
            0.6,
            "Alacritty"
        )
    end)

    hs.hotkey.bind(altShift, "y", function()
        focusOrCreateApp(
            "ORGINDEX-YOUTUBE",
            string.format('open -n -a Alacritty --args -o "window.dimensions.lines=20" -o "window.dimensions.columns=100" --title "ORGINDEX-YOUTUBE" -e zsh -c "cd %s/org/consume && vim %s/org/consume/youtube/youtube1.org"', home, home),
            0.6,
            "Alacritty"
        )
    end)

    hs.hotkey.bind(altShift, "f", function()
        focusOrCreateApp(
            "ORGINDEX-CALORIES",
            string.format('open -n -a Alacritty --args -o "window.dimensions.lines=20" -o "window.dimensions.columns=100" --title "ORGINDEX-CALORIES" -e zsh -c "cd %s/org/life && vim %s/org/life/calories.org"', home, home),
            0.6,
            "Alacritty"
        )
    end)

    -- Nvim Scratchpad: quick note -> clipboard (Cmd+Alt+Ctrl+S)
    hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "s", function()
        focusOrCreateApp(
            "SCRATCHPAD",
            'open -n -a Alacritty --args -o "window.dimensions.lines=20" -o "window.dimensions.columns=100" --title "SCRATCHPAD" -e zsh -lc "nvim-scratchpad"',
            0.6,
            "Alacritty"
        )
    end)

    hs.hotkey.bind(alt, "y", function()
        focusOrCreateApp(
            "YAZI",
            string.format('open -n -a Alacritty --args -o "window.dimensions.lines=20" -o "window.dimensions.columns=100" --title "YAZI" -e zsh -c "yazi"', home),
            0.8,
            "Alacritty"
        )
    end)

    hs.hotkey.bind(altShift, "z", function()
        -- 1. Try to find existing window by stored ID
        local existingWin = state.weekenduoWinId and hs.window(state.weekenduoWinId)
        if existingWin and (not existingWin:application() or not hs.window(state.weekenduoWinId)) then
            existingWin = nil
            state.weekenduoWinId = nil
        end

        -- 2. If ID is missing, try to find by title pattern among all windows (even if launching)
        -- This helps if the marking was missed or we are spaming the keybind
        if not existingWin then
            local allWins = require("nanowm.watchers").getManagedWindows()
            for _, win in ipairs(allWins) do
                local title = (win:title() or ""):lower()
                local app = win:application()
                local appName = app and app:name() or ""

                -- Match Firefox windows that specifically have 'weekenduo' in the title
                if appName == "Firefox" and string.find(title, "weekenduo", 1, true) then
                    existingWin = win
                    state.weekenduoWinId = win:id()
                    state.weekenduoLaunching = false
                    state.triggerSave()
                    print("[NanoWM] Found weekenduo window among existing windows")
                    break
                end
            end
        end

        -- 3. If found, focus it
        if existingWin then
            state.weekenduoLaunching = false -- Reset flag if we found the window
            actions.bringWindowToCurrentContext(existingWin, 0.8)
            return
        end

        -- 4. If not found and not already launching, launch a new one
        if state.weekenduoLaunching then
            print("[NanoWM] Already launching weekenduo, please wait...")
            return
        end

        state.weekenduoLaunching = true
        local sizeFactor = 0.8
        local appName = "Firefox"
        local titlePattern = "weekenduo"
        local launchCmd = '/Applications/Firefox.app/Contents/MacOS/firefox --new-window "https://weekenduo.app"'

        -- Drop any watcher left over from a previous attempt before creating a new one.
        weekenduoCleanup()
        weekenduoFilter = hs.window.filter.new(false):setAppFilter(appName, {allowTitles = titlePattern})
        -- Use windowAllowed instead of windowCreated to catch when title changes during load
        weekenduoFilter:subscribe(hs.window.filter.windowAllowed, function(newWin)
            weekenduoCleanup()
            state.weekenduoLaunching = false -- Reset launching flag
            hs.timer.doAfter(1.0, function()
                if newWin:isValid() and newWin:application() then
                    local screen = newWin:screen():frame()
                    local newW = screen.w * sizeFactor
                    local newH = screen.h * sizeFactor
                    local newX = screen.x + (screen.w - newW) / 2
                    local newY = screen.y + (screen.h - newH) / 2
                    newWin:setFrame({ x = newX, y = newY, w = newW, h = newH })
                    newWin:raise()
                    newWin:focus()
                    layout.tile()
                end
            end)
        end)

        -- Safety timer: on timeout, tear the watcher down as well as resetting the flag.
        -- Resetting the flag alone was what leaked the filter.
        weekenduoTimeout = hs.timer.doAfter(5, function()
            weekenduoTimeout = nil
            weekenduoCleanup()
            if state.weekenduoLaunching then
                state.weekenduoLaunching = false
                print("[NanoWM] Weekenduo launch timed out")
            end
        end)

        core.launchTask("/bin/zsh", { "-c", launchCmd })
    end)

    -- =========================================================================
    -- TIMER MODAL
    -- =========================================================================
    local timerModal = hs.hotkey.modal.new(alt, "t")
    timerModal:bind("", "1", function() integrations.startTimer(5); timerModal:exit() end)
    timerModal:bind("", "2", function() integrations.startTimer(10); timerModal:exit() end)
    timerModal:bind("", "3", function() integrations.startTimer(60); timerModal:exit() end)
    timerModal:bind("", "4", function() integrations.startTimer(120); timerModal:exit() end)
    timerModal:bind("", "n", function() timerModal:exit(); integrations.startCustomTimer() end)
    timerModal:bind("", "r", function() integrations.showTimerRemaining(); timerModal:exit() end)
    timerModal:bind("", "c", function() integrations.cancelTimer(); timerModal:exit() end)
    timerModal:bind("", "escape", function() timerModal:exit() end)

    -- =========================================================================
    -- LEADER KEY MODAL (Nested)
    -- =========================================================================
    local leader = hs.hotkey.modal.new(alt, ",")
    local appsModal = hs.hotkey.modal.new()
    local systemModal = hs.hotkey.modal.new()
    local controlModal = hs.hotkey.modal.new()
    local leaderActive = false

    local function exitAll()
        appsModal:exit()
        systemModal:exit()
        controlModal:exit()
        leader:exit()
    end

    function leader:entered()
        hs.alert.show("Leader: [a]pps [s]ystem [c]ontrol [r]eload [v]im [k] console [y] yazi", 999999)
        leaderActive = true
        tags.updateBorder()
    end

    function leader:exited()
        hs.alert.closeAll()
        leaderActive = false
        tags.updateBorder()
    end

    -- Root level shortcuts
    leader:bind("", "escape", exitAll)
    leader:bind("", "q", exitAll)
    leader:bind("", "y", function()
        focusOrCreateApp(
            "YAZI",
            string.format('open -n -a Alacritty --args -o "window.dimensions.lines=20" -o "window.dimensions.columns=100" --title "YAZI" -e zsh -c "yazi"', home),
            0.8,
            "Alacritty"
        )
        exitAll()
    end)
    leader:bind("", "r", function() hs.reload(); exitAll() end)
    leader:bind("", "k", function() hs.toggleConsole(); exitAll() end)
    leader:bind("", "v", function()
        if _G.vim then _G.vim:enter() end
        exitAll()
    end)

    -- [c]ontrol Sub-modal
    leader:bind("", "c", function()
        hs.alert.closeAll()
        hs.alert.show("Control: [m] Mixer [a] FineTune [w] WiFi [b] Bluetooth", 999999)
        controlModal:enter()
    end)

    controlModal:bind("", "escape", exitAll)
    controlModal:bind("", "q", exitAll)
    controlModal:bind("", "m", function() menus.openAudioMenu(); exitAll() end)
    controlModal:bind("", "a", function() core.toggleFineTune(); exitAll() end)
    controlModal:bind("", "w", function()
        core.openInAlacritty("wifitui", 0.5)
        exitAll()
    end)
    controlModal:bind("", "b", function()
        core.openInAlacritty("btui", 0.5)
        exitAll()
    end)

    -- [a]pps Sub-modal
    leader:bind("", "a", function()
        hs.alert.closeAll()
        hs.alert.show("Apps: [t/a] Alacritty [f/b] Firefox [s] Slack [y] Yazi", 999999)
        appsModal:enter()
    end)

    appsModal:bind("", "escape", exitAll)
    appsModal:bind("", "q", exitAll)
    appsModal:bind("", "y", function()
        focusOrCreateApp(
            "YAZI",
            string.format('open -n -a Alacritty --args -o "window.dimensions.lines=20" -o "window.dimensions.columns=100" --title "YAZI" -e zsh -c "yazi"', home),
            0.8,
            "Alacritty"
        )
        exitAll()
    end)
    appsModal:bind("", "t", function() core.launchTask("/usr/bin/open", { "-n", "-a", "Alacritty" }); exitAll() end)
    appsModal:bind("", "a", function() core.launchTask("/usr/bin/open", { "-n", "-a", "Alacritty" }); exitAll() end)
    appsModal:bind("", "f", function() core.launchTask("/usr/bin/open", { "-n", "-a", "Firefox" }); exitAll() end)
    appsModal:bind("", "b", function() core.launchTask("/usr/bin/open", { "-n", "-a", "Firefox" }); exitAll() end)
    appsModal:bind("", "s", function() core.launchTask("/usr/bin/open", { "-n", "-a", "Slack" }); exitAll() end)

    -- [s]ystem Sub-modal
    leader:bind("", "s", function()
        hs.alert.closeAll()
        hs.alert.show("System: [p] Battery [g] Bar [o] Borders [d] Sync [k/K] Kanata [l] Lock", 999999)
        systemModal:enter()
    end)

    systemModal:bind("", "escape", exitAll)
    systemModal:bind("", "q", exitAll)
    systemModal:bind("", "p", function() integrations.toggleBatterySaver(); exitAll() end)
    systemModal:bind("", "g", function() integrations.toggleSketchybar(); exitAll() end)
    systemModal:bind("", "d", function()
        core.launchSyncMon()
        exitAll()
    end)
    systemModal:bind("", "k", function() integrations.toggleKanata(); exitAll() end)
    systemModal:bind("shift", "k", function() integrations.reloadKanataManual(); exitAll() end)
    systemModal:bind("", "l", function() hs.caffeinate.lockScreen(); exitAll() end)

    -- =========================================================================
    -- INTEGRATIONS
    -- =========================================================================
    hs.hotkey.bind(altShift, "g", integrations.toggleSketchybar)
    hs.hotkey.bind(ctrlAlt, "p", integrations.toggleBatterySaver)
    hs.hotkey.bind(ctrlAltShift, "k", menus.openKanataMenu)

    -- =========================================================================
    -- SYSTEM
    -- =========================================================================
    hs.hotkey.bind(ctrlAltShift, "r", function()
        hs.reload()
        hs.alert.show("NanoWM " .. config.VERSION .. " Reloaded")
    end)
    hs.hotkey.bind(ctrlAltShift, "c", hs.toggleConsole)
    hs.hotkey.bind(cmdAltShift, "c", actions.toggleCaffeinate)
    hs.hotkey.bind(cmdAltShiftCtrl, "l", function() hs.caffeinate.lockScreen() end)
end

return M
