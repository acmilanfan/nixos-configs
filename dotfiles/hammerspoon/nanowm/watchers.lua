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

-- Apps never tracked via AXObserver or window enumeration.
-- rejectApp() only drops Lua callbacks — the C++ AXObserver remains registered
-- and can still freeze the main thread. The fix is filter.new(false) so that
-- these apps never get an AXObserver at all.
local managedExcluded = {
    Hammerspoon = true, Sketchybar = true,
    -- Corporate security / VPN / MDM agents (hourly keepalives hang AX)
    GlobalProtect = true, ["Falcon Notifications"] = true,
    ["Splashtop Streamer"] = true, jamfRemoteAssistConnectorUI = true,
    nbagent = true,
    -- System auth / security daemons
    ["Single Sign-On"] = true, ["Keychain Circle Notification"] = true,
    universalAccessAuthWarn = true, coreautha = true,
    -- Electron / WKWebView renderer subprocesses
    ["Slack Helper"] = true,
    ["Raycast Graphics and Media"] = true, ["Raycast Networking"] = true,
    ["Raycast Web Content"] = true,
    ["nsattributedstringagent Graphics and Media"] = true,
    -- macOS system UI daemons
    Accessibility = true, ["Accessibility Services"] = true,
    ["AirPlay Screen Mirroring"] = true, BackgroundTaskManagementAgent = true,
    ["Control Center"] = true, CoreLocationAgent = true, CoreServicesUIAgent = true,
    Dock = true, ["Notification Center"] = true, PowerChime = true,
    ["Scroll Reverser"] = true, Shortcuts = true,
    SoftwareUpdateNotificationManager = true, Spotlight = true,
    SystemUIServer = true, TextInputMenuAgent = true, TextInputSwitcher = true,
    ["Universal Control"] = true, UserNotificationCenter = true,
    Wallpaper = true, ["Wi-Fi"] = true, WindowManager = true,
    loginwindow = true, talagentd = true,
    -- Accessibility / input utilities (no manageable windows)
    AutoRaise = true, Cursorcerer = true, MiddleClick = true, Warpd = true,
}

-- Only allow AX observers for apps we actually need to manage.
-- Every allowed app gets an AXObserver that can freeze the event loop, so
-- we whitelist rather than blacklist. Add any app whose windows you want to tile.
local managedAllowed = {
    ["Activity Monitor"] = true, Alacritty = true, Arc = true,
    ["App Store"] = true, ["Archive Utility"] = true, Brave = true,
    Calculator = true, Cursor = true, ["Disk Utility"] = true,
    Discord = true, Finder = true, FineTune = true,
    Firefox = true, ["Google Chrome"] = true, IINA = true,
    ["IntelliJ IDEA"] = true, Marta = true, Nextcloud = true,
    ["Photo Booth"] = true, Preview = true, Safari = true,
    Slack = true, Syncthing = true, ["System Settings"] = true,
    Telegram = true, VLC = true, ["Visual Studio Code"] = true,
    Zed = true, ["Force Quit Applications"] = true,
}

-- Apps managed by nanowm but excluded from the AXObserver filter.
-- Their windows are picked up by the 60s resync and by an NSWorkspace activation watcher,
-- not via AXObserver, to avoid their Electron background tasks blocking the AX layer.
local _filterExcluded = {
    Slack = true,       -- Electron; background auth/sync freezes AX for ~30s (confirmed)
    Discord = true,     -- Electron; same risk
}

-- Allowlist mode: AXObservers are set up ONLY for apps we explicitly allow.
-- Excluded apps (corporate agents, system daemons) can never block the AX layer.
local filter = hs.window.filter.new(false)

local function _shouldAllow(app)
    if not app then return false end
    local name = app:name() or ""
    return managedAllowed[name] == true and not managedExcluded[name] and not _filterExcluded[name]
end

for _, app in ipairs(hs.application.runningApplications()) do
    if _shouldAllow(app) then
        filter:allowApp(app:name())
    end
end

-- Event-driven window tracking — no AX polling in the hot path.
-- _trackedWins is maintained by windowCreated/windowDestroyed AXObserver events.
-- _resync() does the full app:allWindows() enumeration on a 60s timer only,
-- with an AX circuit breaker: if any call exceeds 1s, abort and keep existing state.
local _trackedWins = {}
local _axCircuitOpen = false
local _axCircuitUntil = 0

-- Post-wake AX suppression: corporate agents (GlobalProtect, Falcon) reconnect ~40 s
-- after system wake and hold the global AX lock for ~30 s. win:id() itself calls
-- AXUIElementGetWindowID and blocks under that lock, so the guard must fire before
-- any AX call in every callback. Strategy: retile at +2 s (before agents start),
-- suppress for 90 s, then resync+retile when the freeze window has passed.
local _wakeSuppress = false
local _wakeSuppressTimer = nil

local function _resync()
    local now = hs.timer.secondsSinceEpoch()
    if _axCircuitOpen then
        if now < _axCircuitUntil then return end
        _axCircuitOpen = false
    end
    local fresh = {}
    for _, app in ipairs(hs.application.runningApplications()) do
        if app:kind() ~= -1 then
            local appName = app:name() or ""
            if managedAllowed[appName] and not managedExcluded[appName] then
                local t0 = hs.timer.secondsSinceEpoch()
                profiler.lastEvent = "resync:" .. appName
                local appWins = app:allWindows()
                local dt = hs.timer.secondsSinceEpoch() - t0
                if dt >= 1.0 then
                    _axCircuitOpen = true
                    _axCircuitUntil = hs.timer.secondsSinceEpoch() + 90
                    profiler.log("AX circuit open", dt, appName)
                    return
                end
                if profiler.enabled and dt >= 0.10 then
                    profiler.log("resync allWindows() SLOW", dt, appName)
                end
                for _, win in ipairs(appWins) do
                    local id = win:id()
                    if id and id > 0 and win:isStandard() and not win:isMinimized() then
                        fresh[id] = win
                    end
                end
            end
        end
    end
    _trackedWins = fresh
end

-- Screen and geometry watcher
local screenWatcher = nil
-- App and caffeinate watchers — must be module-level to avoid GC after M.setup() returns
local _appWatcher = nil
local _cafWatcher = nil
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

-- Returns the current managed window set from the event-driven tracked table.
-- No AX calls: _trackedWins is updated by windowCreated/windowDestroyed events
-- and corrected every 60s by _resync().
function M.getManagedWindows()
    local wins = {}
    for _, win in pairs(_trackedWins) do
        table.insert(wins, win)
    end
    return wins
end

function M.invalidateManagedWinsCache()
    -- No-op: window list is maintained by AXObserver events, not a TTL cache.
end

function M.setup()
    M.updateScreenFrames()
    screenWatcher = hs.screen.watcher.new(function()
        M.updateScreenFrames()
        if not _wakeSuppress then layout.tile() end
    end)
    screenWatcher:start()

    -- =========================================================================
    -- WINDOW CREATED
    -- =========================================================================
    filter:subscribe(hs.window.filter.windowCreated, profiler.wrap("wf:windowCreated", function(win)
        if _wakeSuppress then return end
        if not win or not win:id() or win:id() == 0 then return end
        local id = win:id()
        _trackedWins[id] = win
        core.registerWindow(win)
        layout.tile()
    end))

    -- =========================================================================
    -- WINDOW TITLE CHANGED
    -- =========================================================================
    filter:subscribe(hs.window.filter.windowTitleChanged, profiler.wrap("wf:titleChanged", function(win)
        if _wakeSuppress then return end
        if not win or not win:id() or win:id() == 0 then return end
        -- Title change may affect title-based float detection; clear cached result
        core.invalidateFloatingCache(win:id())
        core.registerWindow(win)
    end))

    -- =========================================================================
    -- WINDOW DESTROYED
    -- =========================================================================
    filter:subscribe(hs.window.filter.windowDestroyed, profiler.wrap("wf:windowDestroyed", function(win)
        if _wakeSuppress then return end
        if not win then return end

        local id = win:id()
        if not id or id == 0 then return end

        _trackedWins[id] = nil

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
        if _wakeSuppress then return end
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
        if _wakeSuppress then return end
        if not win or not win:id() or win:id() == 0 then return end

        local tag = state.special.active and state.special.tag or state.currentTag
        if not core.isFloating(win) and not state.isTagFree(tag) then
            resizeWatcher:start()
        end
    end))

    -- Populate _trackedWins at startup, then resync every 60s to catch any drift
    -- and pick up windows for _filterExcluded apps (Slack, Discord) that have no AXObserver.
    _resync()
    hs.timer.new(60, _resync):start()

    -- Allow newly launched apps into the filter; trigger a deferred resync for new apps.
    -- The appActivated path for _filterExcluded apps (Slack, Discord) was removed:
    -- app:allWindows() on every Slack activation caused 25 s freezes when corporate agents
    -- held the AX lock. The 60s _resync() timer covers those windows without blocking.
    _appWatcher = hs.application.watcher.new(function(appName, event, app)
        if event == hs.application.watcher.launched then
            if _shouldAllow(app) then filter:allowApp(appName) end
            if managedAllowed[appName] and not managedExcluded[appName] then
                hs.timer.doAfter(1.5, _resync)
            end
        end
    end)
    _appWatcher:start()

    -- After any detected freeze >= 5 s, extend the AX suppress guard for 90 s.
    -- This catches cases where corporate agents reconnect after the caffeinate
    -- guard's initial 300 s window (or when no sleep/wake event fired at all).
    profiler.onFreeze = function(_gap)
        _wakeSuppress = true
        if _wakeSuppressTimer then _wakeSuppressTimer:stop() end
        profiler.log("post-freeze suppress start", 0)
        _wakeSuppressTimer = hs.timer.doAfter(90, function()
            _wakeSuppress = false
            _wakeSuppressTimer = nil
            profiler.log("post-freeze suppress lifted", 0)
            _resync()
            layout.tile()
        end)
    end

    -- Suppress all AX callbacks for 300 s after system wake to avoid blocking on the
    -- corporate-agent reconnect window. Agents reconnect at unpredictable times post-wake
    -- (observed: 40 s–207 s) and hold the global AX lock for ~30 s. win:id() itself calls
    -- AXUIElementGetWindowID and blocks under that lock.
    -- No early retile: the +2 s window is unreliable (caffeinate event arrives late; agents
    -- may already be reconnecting). The 300 s resync+retile fires when AX is safe again.
    -- _cafWatcher must be module-level — Hammerspoon GCs watchers without a live reference.
    _cafWatcher = hs.caffeinate.watcher.new(function(event)
        if event == hs.caffeinate.watcher.systemDidWake then
            _wakeSuppress = true
            if _wakeSuppressTimer then _wakeSuppressTimer:stop() end
            profiler.lastEvent = "wake:suppress"
            profiler.log("wake:suppress start", 0)
            -- +300 s: lift suppression and do a final resync+retile
            _wakeSuppressTimer = hs.timer.doAfter(300, function()
                _wakeSuppress = false
                _wakeSuppressTimer = nil
                profiler.log("wake:suppress lifted", 0)
                _resync()
                layout.tile()
            end)
        end
    end)
    _cafWatcher:start()
end

return M
