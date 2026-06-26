-- =============================================================================
-- NanoWM Window Watchers
-- Window filter event handlers and resize detection
-- =============================================================================

local config = require("nanowm.config")
local state = require("nanowm.state")
local core = require("nanowm.core")
local layout = require("nanowm.layout")
local tags = require("nanowm.tags")
local integrations = require("nanowm.integrations")
local profiler = require("nanowm.profiler")

local M = {}

-- =============================================================================
-- Window Filter Setup
-- =============================================================================

-- Use 'true' to only track standard, visible windows, ignoring background noise
local filter = hs.window.filter.new(true)
filter:rejectApp("Hammerspoon")
filter:rejectApp("Sketchybar")
-- Corporate security/VPN agents: their hourly keepalive/reconnect cycles briefly
-- create AX-accessible windows that block the AXObserver for ~20-30 seconds.
filter:rejectApp("GlobalProtect")
filter:rejectApp("Falcon Notifications")

-- Apps excluded from window enumeration (same as filter rejections above)
local managedExcluded = {
    Hammerspoon = true,
    Sketchybar = true,
    GlobalProtect = true,
    ["Falcon Notifications"] = true,
}

-- Short-lived cache so multiple callers in the same event burst share one allWindows() call
local managedWinsCache = nil
local managedWinsCacheTime = 0

-- Screen and geometry watcher
local screenWatcher = nil
function M.updateScreenFrames()
    state.screenFrames = {}
    for _, s in ipairs(hs.screen.allScreens()) do
        local f = s:frame()
        if state.sketchybarEnabled then
            local name = s:name()
            if name ~= "Built-in Retina Display" and name ~= "Color LCD" then
                f.y = f.y + config.sketchybarHeight
                f.h = f.h - config.sketchybarHeight
            end
        end
        state.screenFrames[s:id()] = { f = f, screen = s }
    end
end

-- Resize watcher for manual mouse resizing
local resizeWatcher = hs.timer.delayed.new(0.3, function()
    layout.handleManualResize()
end)

-- Enumerate windows per-app instead of via hs.window.allWindows() so that when
-- any single app's AX server hangs, we can log WHICH app caused it.
-- Background-only processes (kind == -1) are skipped to avoid unnecessary AX calls.
-- The TTL cache still collapses burst events into 1-2 real enumerations.
function M.getManagedWindows()
    local now = hs.timer.secondsSinceEpoch()
    if managedWinsCache and (now - managedWinsCacheTime) < state.perfProfile().cacheTTL then
        return managedWinsCache
    end

    local _totalT0 = profiler.enabled and hs.timer.secondsSinceEpoch() or 0
    local wins = {}
    for _, app in ipairs(hs.application.runningApplications()) do
        -- Skip background-only daemons that have no windows (kind == -1)
        if app:kind() ~= -1 then
            local appName = app:name() or ""
            if not managedExcluded[appName] then
                local _appT0 = profiler.enabled and hs.timer.secondsSinceEpoch() or 0
                local appWins = app:allWindows()
                if profiler.enabled then
                    local _appDt = hs.timer.secondsSinceEpoch() - _appT0
                    if _appDt >= 0.10 then
                        profiler.log("app:allWindows() SLOW", _appDt, appName)
                    end
                end
                for _, win in ipairs(appWins) do
                    local id = win:id()
                    if id and id > 0 and win:isStandard() and not win:isMinimized() then
                        table.insert(wins, win)
                    end
                end
            end
        end
    end
    if profiler.enabled then
        local _totalDt = hs.timer.secondsSinceEpoch() - _totalT0
        if _totalDt >= profiler.threshold then
            profiler.log("getManagedWindows(total)", _totalDt)
        end
    end
    managedWinsCache = wins
    managedWinsCacheTime = now
    return wins
end

function M.invalidateManagedWinsCache()
    managedWinsCache = nil
end

function M.setup()
    M.updateScreenFrames()
    screenWatcher = hs.screen.watcher.new(function()
        M.updateScreenFrames()
        layout.tile()
    end)
    screenWatcher:start()

    -- =========================================================================
    -- WINDOW CREATED
    -- =========================================================================
    filter:subscribe(hs.window.filter.windowCreated, profiler.wrap("wf:windowCreated", function(win)
        if not win or not win:id() or win:id() == 0 then return end
        managedWinsCache = nil
        core.registerWindow(win)
        layout.tile()
    end))

    -- =========================================================================
    -- WINDOW TITLE CHANGED
    -- =========================================================================
    filter:subscribe(hs.window.filter.windowTitleChanged, profiler.wrap("wf:titleChanged", function(win)
        if not win or not win:id() or win:id() == 0 then return end
        -- Title change may affect title-based float detection; clear cached result
        core.invalidateFloatingCache(win:id())
        core.registerWindow(win)
    end))

    -- =========================================================================
    -- WINDOW DESTROYED
    -- =========================================================================
    filter:subscribe(hs.window.filter.windowDestroyed, profiler.wrap("wf:windowDestroyed", function(win)
        if not win then return end

        local id = win:id()
        if not id or id == 0 then return end

        managedWinsCache = nil

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
            core.invalidateFloatingCache(id)

            if tag then
                core.resetMasterWidthIfNeeded(tag)
            end

            state.pendingDestruction[id] = nil
            state.triggerSave()
            layout.tile()
        end)
    end))

    -- =========================================================================
    -- WINDOW FOCUSED
    -- =========================================================================
    filter:subscribe(hs.window.filter.windowFocused, profiler.wrap("wf:windowFocused", function(win)
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
            if tag == currentContextTag then
                win:raise()
                integrations.updateSketchybar()
            else
                -- Floating window parked off-screen on another tag: mark that tag urgent
                -- instead of raising an invisible window
                tags.markTagUrgent(tag)
            end
            return
        end

        if not tag or tag == state.currentTag then
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
    end))

    -- =========================================================================
    -- WINDOW MOVED (for resize detection)
    -- =========================================================================
    filter:subscribe(hs.window.filter.windowMoved, profiler.wrap("wf:windowMoved", function(win)
        if not win or not win:id() or win:id() == 0 then return end

        local tag = state.special.active and state.special.tag or state.currentTag
        if not core.isFloating(win) and not state.isTagFree(tag) then
            resizeWatcher:start()
        end
    end))
end

return M
