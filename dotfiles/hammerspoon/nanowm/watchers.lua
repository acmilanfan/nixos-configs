-- =============================================================================
-- NanoWM Window Watchers
-- Window filter event handlers and resize detection
-- =============================================================================

local config = require("nanowm.config")
local state = require("nanowm.state")
local core = require("nanowm.core")
local layout = require("nanowm.layout")
local tags = require("nanowm.tags")

local M = {}

-- =============================================================================
-- Window Filter Setup
-- =============================================================================

-- Use 'true' to only track standard, visible windows, ignoring background noise
local filter = hs.window.filter.new(true)
filter:rejectApp("Hammerspoon")
filter:rejectApp("Sketchybar")

-- Resize watcher for manual mouse resizing
local resizeWatcher = hs.timer.delayed.new(0.3, function()
    layout.handleManualResize()
end)

function M.getManagedWindows()
    local wins = {}
    for _, win in ipairs(filter:getWindows()) do
        if win:id() and win:id() > 0 then
            table.insert(wins, win)
        end
    end
    return wins
end

function M.setup()
    -- =========================================================================
    -- WINDOW CREATED
    -- =========================================================================
    filter:subscribe(hs.window.filter.windowCreated, function(win)
        if not win or not win:id() or win:id() == 0 then return end
        core.registerWindow(win)
        layout.tile()
    end)

    -- =========================================================================
    -- WINDOW TITLE CHANGED
    -- =========================================================================
    filter:subscribe(hs.window.filter.windowTitleChanged, function(win)
        if not win or not win:id() or win:id() == 0 then return end
        -- Skip already-registered windows unless we're hunting for the weekenduo title change
        if state.tags[win:id()] and not state.markNextWeekenduo then return end
        core.registerWindow(win)
    end)

    -- =========================================================================
    -- WINDOW DESTROYED
    -- =========================================================================
    filter:subscribe(hs.window.filter.windowDestroyed, function(win)
        if not win then return end

        local id = win:id()
        if not id or id == 0 then return end

        local idStr = tostring(id)
        local tag = state.tags[id]
        local app = win:application()
        local appName = app and app:name() or "Unknown"

        -- Cancel any existing pending destruction
        if state.pendingDestruction[id] and state.pendingDestruction[id].timer then
            state.pendingDestruction[id].timer:stop()
        end

        -- Store for potential recovery
        state.pendingDestruction[id] = {
            tag = tag,
            appName = appName,
            time = hs.timer.secondsSinceEpoch(),
        }

        -- Delay the actual cleanup
        state.pendingDestruction[id].timer = hs.timer.doAfter(config.destructionDelay, function()
            local stillExists = hs.window(id)
            if stillExists then
                print("[NanoWM] Window " .. tostring(id) .. " reappeared, not cleaning up")
                state.pendingDestruction[id] = nil
                return
            end

            print("[NanoWM] Cleaning up destroyed window: " .. appName ..
                " (id: " .. tostring(id) .. ") was on tag " .. tostring(tag))

            -- Remove from ALL stacks and creation orders
            for _, stack in pairs(state.stacks) do
                for i = #stack, 1, -1 do
                    if stack[i] == id then
                        table.remove(stack, i)
                    end
                end
            end
            for _, order in pairs(state.tagCreationOrder or {}) do
                for i = #order, 1, -1 do
                    if order[i] == id then
                        table.remove(order, i)
                    end
                end
            end

            if id == state.weekenduoWinId then
                state.weekenduoWinId = nil
                print("[NanoWM] Cleared weekenduo window ID")
            end

            state.tags[id] = nil
            state.sticky[id] = nil
            state.floatingOverrides[id] = nil
            state.windowState[id] = nil

            if state.floatingCache then state.floatingCache[idStr] = nil end
            if state.fullscreenCache then state.fullscreenCache[idStr] = nil end
            if state.sizeCache then state.sizeCache[idStr] = nil end

            if tag then
                core.resetMasterWidthIfNeeded(tag)
            end

            state.pendingDestruction[id] = nil
            state.triggerSave()
            layout.tile()
        end)
    end)

    -- =========================================================================
    -- WINDOW FOCUSED
    -- =========================================================================
    filter:subscribe(hs.window.filter.windowFocused, function(win)
        if not win or not win:id() or win:id() == 0 then return end
        if state.launching then return end

        local id = win:id()
        local tag = state.tags[id]

        if tag then
            state.tagLastFocused[tag] = id
        end

        -- If it's a window on the current tag (or special), and it's tiled, we might need to re-tile (for scrolling layout)
        local currentContextTag = state.special.active and state.special.tag or state.currentTag
        if tag == currentContextTag and not core.isFloating(win) then
            if state.getLayout(tag) == "scrolling" then
                layout.tile()
            end
            return
        end

        -- Anti-jump protection for cross-tag focus
        local timeSinceTile = hs.timer.secondsSinceEpoch() - state.lastTileTime
        if timeSinceTile < config.tileProtectionWindow then return end

        local timeSinceSwitch = hs.timer.secondsSinceEpoch() - state.lastManualTagSwitch
        if timeSinceSwitch < config.tagSwitchCooldown then return end

        if core.isFloating(win) then
            win:raise()
            return
        end

        if not tag or tag == state.currentTag or tag == "special" then
            return
        end

        if state.special.active and tag == state.special.tag then
            return
        end

        -- Check if triggered by Dock click
        local isDockClick = core.isMouseInDockArea()

        if isDockClick then
            print("[NanoWM] Dock click detected, switching to tag " .. tostring(tag))
            if tag == "special" then
                if not state.special.active then
                    tags.toggleSpecial()
                end
            else
                tags.gotoTag(tag)
            end
            hs.timer.doAfter(0.05, function()
                win:focus()
            end)
        else
            tags.markTagUrgent(tag)
        end

        if state.focusTimer then
            state.focusTimer:stop()
            state.focusTimer = nil
        end
    end)

    -- =========================================================================
    -- WINDOW MOVED (for resize detection)
    -- =========================================================================
    filter:subscribe(hs.window.filter.windowMoved, function(win)
        if not win or not win:id() or win:id() == 0 then return end

        local tag = state.special.active and state.special.tag or state.currentTag
        if not core.isFloating(win) and not state.isTagFree(tag) then
            resizeWatcher:start()
        end
    end)
end

return M
