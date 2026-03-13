-- =============================================================================
-- NanoWM Core Functions
-- Window registration, floating detection, and core helpers
-- =============================================================================

local config = require("nanowm.config")
local state = require("nanowm.state")

local M = {}

-- =============================================================================
-- Floating Detection
-- =============================================================================

function M.isFloating(win)
    if not win then return false end

    local id = win:id()

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

    -- Check app-based floating
    local app = win:application()
    if not app then return false end

    if config.floatingApps[app:name()] then
        return true
    end

    -- Check title-based floating
    local title = (win:title() or ""):lower()
    for _, str in ipairs(config.floatingTitles) do
        if string.find(title, str:lower(), 1, true) then
            return true
        end
    end

    -- Picture-in-Picture always floats
    if title == "Picture-in-Picture" then
        return true
    end

    return win:isStandard() == false
end

-- =============================================================================
-- Window Registration
-- =============================================================================

function M.registerWindow(win)
    local id = win:id()
    local title = (win:title() or ""):lower()

    if state.markNextWeekenduo and string.find(title, "weekenduo", 1, true) then
        state.weekenduoWinId = id
        state.markNextWeekenduo = false
        print("[NanoWM] Marked weekenduo window ID: " .. tostring(id))
    end

    if not state.tags[id] then
        local app = win:application()
        local appName = app and app:name() or "Unknown"

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
        end

        state.triggerSave()
    end
end

-- =============================================================================
-- Window Queries
-- =============================================================================

function M.getTiledWindows(tag)
    local stackIds = state.stacks[tag] or {}
    local windows = {}
    local cleanStack = {}

    for _, id in ipairs(stackIds) do
        local win = hs.window.get(id)
        if win and win:isVisible() and state.tags[id] == tag then
            if not M.isFloating(win) then
                table.insert(windows, win)
                table.insert(cleanStack, id)
            end
        elseif hs.window.get(id) and state.tags[id] == tag then
            table.insert(cleanStack, id)
        end
    end

    local allWins = hs.window.filter.default:getWindows()
    for _, win in ipairs(allWins) do
        local id = win:id()
        if state.tags[id] == tag and not M.isFloating(win) then
            local inStack = false
            for _, sid in ipairs(cleanStack) do
                if sid == id then
                    inStack = true
                    break
                end
            end
            if not inStack then
                table.insert(windows, 1, win)
                table.insert(cleanStack, 1, id)
            end
        end
    end

    if #cleanStack ~= #stackIds then
        state.stacks[tag] = cleanStack
        state.triggerSave()
    end

    return windows
end

function M.getAllVisibleWindows()
    local tag = state.special.active and state.special.tag or state.currentTag
    local list = M.getTiledWindows(tag)

    for _, win in ipairs(hs.window.filter.default:getWindows()) do
        local id = win:id()
        local isSticky = state.sticky[id]
        local isFloat = M.isFloating(win)
        local onTag = (state.tags[id] == tag)
        local isPip = (win:title() == "Picture-in-Picture")

        if not isPip and ((isFloat and onTag) or isSticky) then
            local seen = false
            for _, w in ipairs(list) do
                if w:id() == id then
                    seen = true
                    break
                end
            end
            if not seen then
                table.insert(list, win)
            end
        end
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

function M.isMouseInDockArea()
    local mousePos = hs.mouse.absolutePosition()
    local screen = hs.screen.mainScreen()
    local screenFrame = screen:frame()

    local dockPos = hs.execute("defaults read com.apple.dock orientation 2>/dev/null"):gsub("%s+", "")
    if dockPos == "" then
        dockPos = "bottom"
    end

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
