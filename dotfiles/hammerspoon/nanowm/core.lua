-- =============================================================================
-- NanoWM Core Functions
-- Window registration, floating detection, and core helpers
-- =============================================================================

local config = require("nanowm.config")
local state = require("nanowm.state")

local M = {}

-- =============================================================================
-- Window Map Cache
-- hs.window.allWindows() hits the Accessibility API and is expensive.
-- Cache the result for 100ms so multiple getTiledWindows calls in the same
-- tile cycle (layout + sketchybar update) share one enumeration.
-- =============================================================================

local winMapCache = nil
local winMapCacheTime = 0

local function getWinMap()
    local now = hs.timer.secondsSinceEpoch()
    if not winMapCache or (now - winMapCacheTime) > 0.1 then
        winMapCache = {}
        winMapCacheTime = now
        for _, win in ipairs(require("nanowm.watchers").getManagedWindows()) do
            winMapCache[win:id()] = win
        end
    end
    return winMapCache
end

-- =============================================================================
-- isFloating Result Cache
-- win:application(), app:name(), win:title(), and win:isStandard() are all
-- Accessibility API calls. For most windows these results never change during
-- a session, so we cache them per window ID.
-- Volatile checks (weekenduoWinId, floatingOverrides, sticky) are evaluated
-- before the cache and bypass it, so no invalidation is needed for those.
-- Invalidate on: window destroyed, window title changed (title-based floats).
-- =============================================================================

local isFloatingResultCache = {}

function M.invalidateFloatingCache(id)
    isFloatingResultCache[id] = nil
end

-- =============================================================================
-- Floating Detection
-- =============================================================================

function M.isFloating(win)
    if not win then return false end

    local id = win:id()
    if not id or id == 0 then return true end

    -- Special case for weekenduo
    if state.weekenduoWinId == id then
        return true
    end

    -- Check explicit override
    if state.floatingOverrides[id] ~= nil then
        return state.floatingOverrides[id]
    end

    -- Sticky windows are always floating
    if state.sticky[id] then
        return true
    end

    -- Check cached result for the expensive Accessibility calls below
    local cached = isFloatingResultCache[id]
    if cached ~= nil then return cached end

    -- Check app-based floating
    local app = win:application()
    if not app then
        isFloatingResultCache[id] = false
        return false
    end

    local result
    if config.floatingApps[app:name()] then
        result = true
    else
        -- Check title-based floating
        local title = (win:title() or ""):lower()
        result = false
        for _, str in ipairs(config.floatingTitles) do
            if string.find(title, str:lower(), 1, true) then
                result = true
                break
            end
        end
        if not result then
            result = (title == "picture-in-picture") or (win:isStandard() == false)
        end
    end

    isFloatingResultCache[id] = result
    return result
end

-- =============================================================================
-- Window Registration
-- =============================================================================

function M.registerWindow(win)
    local id = win:id()
    local title = (win:title() or ""):lower()
    local app = win:application()
    local appName = app and app:name() or "Unknown"

    -- Mark the weekenduo window only if we are explicitly looking for it (triggered by keybind)
    local isWeekenduoTitle = string.find(title, "weekenduo", 1, true)

    if state.markNextWeekenduo and isWeekenduoTitle then
        state.weekenduoWinId = id
        state.markNextWeekenduo = false
        state.weekenduoLaunching = false -- Reset launching flag when window is found
        state.triggerSave()
        print("[NanoWM] Weekenduo window marked: " .. tostring(id))
    elseif isWeekenduoTitle and state.weekenduoLaunching and appName == "Firefox" then
        -- Also reset flag if we find a matching window while launching, even if not perfect
        state.weekenduoLaunching = false
    end

    if not state.tags[id] then
        local rememberedTag = state.getRememberedTag(win)
        local targetTag

        if rememberedTag then
            targetTag = rememberedTag
            print("[NanoWM] Window opened with remembered tag: " .. tostring(rememberedTag))
        else
            -- Check if this app recently had a window destroyed (crash recovery)
            local now = hs.timer.secondsSinceEpoch()
            local recoveryTag = nil
            for oldId, info in pairs(state.pendingDestruction) do
                if info.appName == appName and info.tag and (now - info.time) < 2.0 then
                    recoveryTag = info.tag
                    print("[NanoWM] Crash recovery: " .. appName .. " was on tag " .. tostring(recoveryTag))
                    if info.timer then
                        info.timer:stop()
                    end
                    state.pendingDestruction[oldId] = nil
                    break
                end
            end

            if recoveryTag then
                targetTag = recoveryTag
            else
                targetTag = state.special.active and state.special.tag or state.currentTag
            end
        end

        state.tags[id] = targetTag

        if not M.isFloating(win) then
            if not state.stacks[targetTag] then
                state.stacks[targetTag] = {}
            end
            local found = false
            for _, existingId in ipairs(state.stacks[targetTag]) do
                if existingId == id then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(state.stacks[targetTag], 1, id)
            end

            if not state.tagCreationOrder[targetTag] then
                state.tagCreationOrder[targetTag] = {}
            end
            local foundInCreation = false
            for _, existingId in ipairs(state.tagCreationOrder[targetTag]) do
                if existingId == id then
                    foundInCreation = true
                    break
                end
            end
            if not foundInCreation then
                table.insert(state.tagCreationOrder[targetTag], id)
            end
        end

        state.triggerSave()
    end
end

-- =============================================================================
-- Window Queries
-- =============================================================================

function M.getTiledWindows(tag, allWins)
    local stackIds = state.stacks[tag] or {}
    local windows = {}
    local cleanStack = {}
    local seenIds = {}

    local winMap = getWinMap()

    for _, id in ipairs(stackIds) do
        if not seenIds[id] then
            local win = winMap[id]
            if win and state.tags[id] == tag then
                local isVisible = win:isVisible()
                local isCurrentOrSpecial = (tag == state.currentTag or tag == state.special.tag)

                -- Include if visible OR if it's on the current/special tag and not minimized
                if isVisible or (isCurrentOrSpecial and not win:isMinimized()) then
                    if not M.isFloating(win) then
                        table.insert(windows, win)
                        table.insert(cleanStack, id)
                        seenIds[id] = true
                    end
                else
                    -- Still on tag but not visible/minimized and not current tag
                    table.insert(cleanStack, id)
                    seenIds[id] = true
                end
            end
        end
    end

    allWins = allWins or require("nanowm.watchers").getManagedWindows()
    for _, win in ipairs(allWins) do
        local id = win:id()
        if state.tags[id] == tag and not M.isFloating(win) and not seenIds[id] then
            table.insert(windows, 1, win)
            table.insert(cleanStack, 1, id)
            seenIds[id] = true
        end
    end

    if #cleanStack ~= #stackIds then
        state.stacks[tag] = cleanStack
        state.triggerSave()
    end

    return windows
end

function M.getWindowsInCreationOrder(tag, allWins)
    local orderIds = state.tagCreationOrder[tag] or {}
    local windows = {}
    local cleanOrder = {}
    local seenIds = {}

    local winMap = getWinMap()

    for _, id in ipairs(orderIds) do
        if not seenIds[id] then
            local win = winMap[id]
            if win and state.tags[id] == tag then
                local isVisible = win:isVisible()
                local isCurrentOrSpecial = (tag == state.currentTag or tag == state.special.tag)

                if isVisible or (isCurrentOrSpecial and not win:isMinimized()) then
                    if not M.isFloating(win) then
                        table.insert(windows, win)
                        table.insert(cleanOrder, id)
                        seenIds[id] = true
                    end
                else
                    -- Still on tag but not visible/minimized and not current tag
                    table.insert(cleanOrder, id)
                    seenIds[id] = true
                end
            end
        end
    end

    -- Check for missing windows in creation order that should be there
    allWins = allWins or require("nanowm.watchers").getManagedWindows()
    for _, win in ipairs(allWins) do
        local id = win:id()
        if state.tags[id] == tag and not M.isFloating(win) and not seenIds[id] then
            table.insert(windows, win)
            table.insert(cleanOrder, id)
            seenIds[id] = true
        end
    end

    if #cleanOrder ~= #orderIds then
        state.tagCreationOrder[tag] = cleanOrder
        state.triggerSave()
    end

    return windows
end

function M.getAllVisibleWindows()
    local tag = state.special.active and state.special.tag or state.currentTag
    local list = M.getTiledWindows(tag)
    local seenIds = {}
    for _, win in ipairs(list) do
        seenIds[win:id()] = true
    end

    -- Add floating windows on this tag, and sticky windows.
    -- Collect them first, then sort by window ID for a stable cycle order.
    -- getManagedWindows() returns windows in z-order (recently focused first),
    -- so without sorting, focusing a floater shifts its list position on the next
    -- call, trapping cycleFocus in a loop between the two floaters.
    -- We also exclude windows parked off-screen (x>=90000) so hidden floating
    -- windows don't appear as silent cycle stops.
    local toAdd = {}
    for _, win in ipairs(require("nanowm.watchers").getManagedWindows()) do
        local id = win:id()
        if not seenIds[id] then
            local isSticky = state.sticky[id]
            local onTag = (state.tags[id] == tag)
            local isPip = (win:title() == "Picture-in-Picture")

            if not isPip and ((M.isFloating(win) and onTag) or isSticky) then
                local f = win:frame()
                if f.x < 90000 then
                    table.insert(toAdd, win)
                    seenIds[id] = true
                end
            end
        end
    end
    table.sort(toAdd, function(a, b) return a:id() < b:id() end)
    for _, win in ipairs(toAdd) do
        table.insert(list, win)
    end

    return list
end

-- =============================================================================
-- Master Width Management
-- =============================================================================

function M.resetMasterWidthIfNeeded(tag)
    tag = tag or state.currentTag
    local windows = M.getTiledWindows(tag)
    if #windows <= 1 then
        state.masterWidths[tag] = config.defaultMasterWidth
        state.triggerSave()
    end
end

-- =============================================================================
-- Dock Detection
-- =============================================================================

-- Cache dock orientation — it changes only when the user moves the dock
local cachedDockPos = nil

function M.isMouseInDockArea()
    local mousePos = hs.mouse.absolutePosition()
    local screen = hs.screen.mainScreen()
    local screenFrame = screen:frame()

    if not cachedDockPos then
        cachedDockPos = hs.execute("defaults read com.apple.dock orientation 2>/dev/null"):gsub("%s+", "")
        if cachedDockPos == "" then cachedDockPos = "bottom" end
    end
    local dockPos = cachedDockPos

    local dockThreshold = 90

    if dockPos == "bottom" then
        return mousePos.y >= (screenFrame.y + screenFrame.h - dockThreshold)
    elseif dockPos == "left" then
        return mousePos.x <= (screenFrame.x + dockThreshold)
    elseif dockPos == "right" then
        return mousePos.x >= (screenFrame.x + screenFrame.w - dockThreshold)
    end

    return false
end

-- =============================================================================
-- Utility Functions
-- =============================================================================

function M.launchTask(cmd, args)
    state.launching = true
    hs.task.new(cmd, nil, args):start()
    hs.timer.doAfter(2.0, function()
        state.launching = false
    end)
end

function M.openInAlacritty(command, sizeFactor)
    -- Include common paths where wifitui or blueutil-tui might be located
    -- Using -n to ensure a NEW window is opened even if Alacritty is already running
    -- Using -e to run the command
    local shellCmd = string.format("export PATH=$PATH:/opt/homebrew/bin:/usr/local/bin:/run/current-system/sw/bin; %s; zsh", command)
    local fullCmd = string.format("/usr/bin/open -n -a Alacritty --args --title '%s' -e zsh -c \"%s\"", command, shellCmd)

    if sizeFactor then
        -- Watch for the specific window title we just set
        local filter = hs.window.filter.new(false):setAppFilter("Alacritty", {allowTitles = command})
        filter:subscribe(hs.window.filter.windowCreated, function(newWin)
            filter:unsubscribe()
            -- Give it a bit more time to fully initialize and be recognized by NanoWM
            hs.timer.doAfter(0.8, function()
                if newWin:isValid() then
                    local screen = newWin:screen():frame()
                    local newW = screen.w * sizeFactor
                    local newH = screen.h * sizeFactor
                    local newX = screen.x + (screen.w - newW) / 2
                    local newY = screen.y + (screen.h - newH) / 2
                    newWin:setFrame({ x = newX, y = newY, w = newW, h = newH })
                    newWin:raise()
                    newWin:focus()
                end
            end)
        end)
    end

    hs.task.new("/bin/zsh", nil, { "-c", fullCmd }):start()
end

function M.toggleFineTune()
    -- FineTune is a menu-bar app. We'll try multiple ways to trigger it.
    local app = hs.application.get("FineTune")
    if app then
        app:activate()

        -- Try clicking the status item (menu bar 2) by name or index
        -- If the menu bar is hidden, we might need to be more aggressive
        local script = [[
            tell application "System Events"
                tell process "FineTune"
                    -- Try to find the status item in menu bar 2
                    try
                        -- Method 1: Click the first item in the status area (menu bar 2)
                        click menu bar item 1 of menu bar 2
                    on error
                        try
                            -- Method 2: If menu bar 2 fails, try menu bar 1 (sometimes apps behave differently)
                            click menu bar item 1 of menu bar 1
                        end try
                    end try
                end tell
            end tell
        ]]
        hs.osascript.applescript(script)

        -- Fallback: If it has windows now, center them
        hs.timer.doAfter(0.5, function()
            local wins = app:allWindows()
            if #wins > 0 then
                local win = wins[1]
                win:raise()
                win:focus()
                if M.isFloating(win) then
                    local screen = win:screen():frame()
                    local frame = win:frame()
                    win:setFrame({
                        x = screen.x + (screen.w - frame.w) / 2,
                        y = screen.y + (screen.h - frame.h) / 2,
                        w = frame.w,
                        h = frame.h
                    })
                end
            end
        end)
    else
        -- If not running, launch it
        hs.application.launchOrFocus("FineTune")
    end
end

return M
