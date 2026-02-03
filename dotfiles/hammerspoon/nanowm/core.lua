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
    local title = win:title() or ""
    for _, str in ipairs(config.floatingTitles) do
        if string.find(title, str) then
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

return M
