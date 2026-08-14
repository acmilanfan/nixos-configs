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

-- Only allow AX observers for apps we actually need to manage.
-- Every allowed app gets an AXObserver that can freeze the event loop, so this is an
-- allowlist, not a denylist. Add any app whose windows you want tiled.
--
-- A 44-entry `managedExcluded` denylist used to sit here, tested at five call sites. The
-- filter is built with hs.window.filter.new(false), so nothing is observed unless it appears
-- below -- and the two lists were entirely disjoint, making every `not managedExcluded[...]`
-- test a constant true. Removed as dead code, but the knowledge is worth keeping, because it
-- is the reason this is an allowlist in the first place:
--
--   NEVER add these -- they hang the AX layer, or have no manageable windows:
--     corporate security / VPN / MDM . GlobalProtect, Falcon Notifications,
--         Splashtop Streamer, jamfRemoteAssistConnectorUI, nbagent
--     auth / security daemons ........ Single Sign-On, Keychain Circle Notification,
--         universalAccessAuthWarn, coreautha
--     Electron / WKWebView renderers . Slack Helper, Raycast {Graphics and Media,
--         Networking, Web Content}, nsattributedstringagent Graphics and Media
--     macOS UI daemons ............... Dock, Control Center, Notification Center, Spotlight,
--         SystemUIServer, WindowManager, Wallpaper, loginwindow, talagentd, Accessibility,
--         AirPlay Screen Mirroring, CoreLocationAgent, PowerChime, Shortcuts, Wi-Fi, ...
--     input utilities ................ AutoRaise, Cursorcerer, MiddleClick, Warpd
local managedAllowed = {
    ["Activity Monitor"] = true, Alacritty = true, Arc = true,
    ["App Store"] = true, ["Archive Utility"] = true, Brave = true,
    Calculator = true, Cursor = true, ["Disk Utility"] = true,
    Discord = true, Finder = true, FineTune = true,
    Firefox = true, ["Google Chrome"] = true, IINA = true,
    ["IntelliJ IDEA"] = true, Marta = true, Nextcloud = true,
    ["Photo Booth"] = true, Preview = true, Safari = true,
    Slack = true, Syncthing = true, ["System Settings"] = true,
    Telegram = true, UTM = true, VLC = true, ["Visual Studio Code"] = true,
    Zed = true, ["Force Quit Applications"] = true,
}

-- Allowlist mode: AXObservers are set up ONLY for apps we explicitly allow, so the
-- daemons and corporate agents listed above can never block the AX layer.
local filter = hs.window.filter.new(false)

local function _shouldAllow(app)
    if not app then return false end
    return managedAllowed[app:name() or ""] == true
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

-- Post-wake AX suppression. win:id() calls AXUIElementGetWindowID and blocks under a held
-- AX lock, so the guard has to fire before any AX call in every callback.
--
-- This window was 300 s, sized against "corporate agents reconnect 40-207 s post-wake and
-- hold the lock ~30 s". Reduced to 45 s for two reasons:
--   1. Reclassifying the freeze log found no event matching that ~30 s lock signature. The
--      24-29 s freezes that looked like it were all hourly-aligned -- they were the prune
--      sweep (see state.lua), which has since been fixed.
--   2. Suppression no longer has to be the only defence. Every AX enumeration now trips the
--      circuit breaker below, so a lock that appears at, say, +150 s is caught reactively
--      instead of needing a blanket 5-minute window guessed in advance.
-- Cost of being wrong is bounded: the first slow enumeration after the window trips the
-- breaker and backs everything off for AX_BACKOFF anyway.
-- Wake suppression is evidence-driven, not a fixed guess. On wake, AX is probed immediately:
-- if it answers (normal case) nothing is suppressed at all. Only a probe that fails engages
-- suppression, which then lifts as soon as a later probe succeeds. WAKE_SUPPRESS_MAX is a
-- ceiling for the case where the probe never recovers.
local WAKE_SUPPRESS_MAX   = 45    -- hard ceiling, lift regardless
local WAKE_PROBE_INTERVAL = 2     -- how often to test whether AX is answering again
local AX_PROBE_OK         = 0.25  -- a healthy system-wide attribute read is sub-millisecond
local _wakeSuppress = false
local _wakeSuppressTimer = nil
local _wakeProbeTimer = nil
local _wakeSuppressUntil = 0  -- absolute epoch time when current suppression expires

-- Slow-AX detection, shared by every path that enumerates windows.
-- Previously only _resync() could trip the breaker, and only _resync() checked it. Since
-- _resync runs on a 60s timer while the per-focus and per-second scans run orders of
-- magnitude more often, the breaker never fired in practice (0 occurrences across a
-- multi-hour log containing 27 recorded freezes) — the lock was always hit by a hot path
-- that neither tripped nor honoured it.
local AX_SLOW    = 1.0   -- a single app:allWindows() at/above this means AX is locked
local AX_BACKOFF = 90    -- seconds to stop touching AX once tripped

local function _axTrip(dt, appName)
    _axCircuitOpen = true
    _axCircuitUntil = hs.timer.secondsSinceEpoch() + AX_BACKOFF
    profiler.log("AX circuit open", dt, appName)
end

-- True when AX enumeration must be skipped: post-wake suppression or an open breaker.
local function _axBlocked()
    if _wakeSuppress then return true end
    if not _axCircuitOpen then return false end
    if hs.timer.secondsSinceEpoch() < _axCircuitUntil then return true end
    _axCircuitOpen = false
    return false
end

M.axBlocked = _axBlocked

-- Minimal AX health check: one attribute read on the system-wide element. Orders of magnitude
-- cheaper than app:allWindows(), but it goes through the same global AX lock, so it blocks
-- precisely when the lock is held — which is the signal we want. A healthy read is
-- sub-millisecond; anything at AX_SLOW or beyond trips the breaker so every other path backs
-- off too.
-- Touch hs.axuielement once at load so the extension is resolved now rather than lazily during
-- the first post-wake probe, where it added ~28 ms (measured) to the very call whose latency
-- decides whether AX is healthy.
local _ = hs.axuielement

local function _axProbeHealthy()
    local t0 = hs.timer.secondsSinceEpoch()
    local ok = pcall(function()
        return hs.axuielement.systemWideElement():attributeValue("AXFocusedApplication")
    end)
    local dt = hs.timer.secondsSinceEpoch() - t0
    if dt >= AX_SLOW then
        _axTrip(dt, "wake probe")
        return false
    end
    return ok and dt < AX_PROBE_OK
end

-- Cached Firefox handle for the Firefox scanner below.
-- hs.application.get(name) costs ~2 ms when the app is running but ~50 ms when it is NOT
-- (measured: it falls back to a bundle-ID / Launch Services lookup). The scanner fires every
-- tick, so an unguarded lookup burned ~50 ms per tick the whole time Firefox
-- was closed. Cache the handle, and back off the lookup on a miss.
-- isRunning() returns false for a relaunched instance too, so a stale handle self-invalidates.
local _ffApp = nil
local _ffLookupAt = 0
local FF_LOOKUP_BACKOFF = 10  -- seconds between lookups while Firefox is absent
-- (the scanner below runs every 3 s; see M._ffScanTimer)

local function _resync()
    if _axBlocked() then return end
    local fresh = {}
    for _, app in ipairs(hs.application.runningApplications()) do
        if app:kind() ~= -1 then
            local appName = app:name() or ""
            if managedAllowed[appName] then
                local t0 = hs.timer.secondsSinceEpoch()
                profiler.lastEvent = "resync:" .. appName
                local appWins = app:allWindows()
                local dt = hs.timer.secondsSinceEpoch() - t0
                if dt >= AX_SLOW then _axTrip(dt, appName) end
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

    local untaggedFound = false
    for _, win in pairs(fresh) do
        local wid = win:id()
        if wid and not state.tags[wid] then
            core.registerWindow(win)
            untaggedFound = true
        end
    end
    if untaggedFound then
        layout.tile()
    end
end

-- Lift AX suppression and reconcile. Idempotent; safe from either the probe or the ceiling.
local function _liftSuppress(reason)
    if not _wakeSuppress then return end
    _wakeSuppress = false
    _wakeSuppressUntil = 0
    if _wakeSuppressTimer then _wakeSuppressTimer:stop(); _wakeSuppressTimer = nil end
    if _wakeProbeTimer then _wakeProbeTimer:stop(); _wakeProbeTimer = nil end
    profiler.log("suppress lifted (" .. reason .. ")", 0)
    _resync()
    layout.tile()
end

-- Suppress AX handling, then probe out of it as soon as AX answers. `ceiling` is only a
-- backstop for the case where the probe never recovers.
--
-- Both entry points (system wake, and a detected freeze) share this, so neither can leave a
-- fixed-duration stall behind: previously a freeze armed a flat 90 s suppression that even
-- direct evidence of a healthy AX layer would not clear.
local function _suppressUntilHealthy(reason, ceiling)
    ceiling = ceiling or WAKE_SUPPRESS_MAX
    _wakeSuppress = true
    _wakeSuppressUntil = hs.timer.secondsSinceEpoch() + ceiling
    if _wakeSuppressTimer then _wakeSuppressTimer:stop() end
    if _wakeProbeTimer then _wakeProbeTimer:stop() end
    profiler.log("suppress start (" .. reason .. ")", 0)
    _wakeSuppressTimer = hs.timer.doAfter(ceiling, function() _liftSuppress("ceiling") end)
    _wakeProbeTimer = hs.timer.new(WAKE_PROBE_INTERVAL, function()
        if not _wakeSuppress then return end
        if _axProbeHealthy() then _liftSuppress("probe ok") end
    end)
    _wakeProbeTimer:start()
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

-- Scans allowlisted apps for unmanaged standard windows and adds them to _trackedWins,
-- catching windows the hs.window.filter AXObserver missed (e.g. a Firefox tab detached
-- into a new window).
--
-- onlyApp: when supplied, scan just that application. windowFocused passes the focused
-- app — enumerating every allowlisted app on every focus event (so: every Alt+J/K and
-- every mouse click) was the hottest AX path in the config, despite the original comment
-- here claiming it only scanned the focused app.
--
-- With no onlyApp the full sweep still runs, but rate-limited: within the cooldown the
-- window set is covered by windowCreated events, the 1s Firefox scanner and the 60s
-- resync anyway.
local _lastFullAugment = 0
local FULL_AUGMENT_COOLDOWN = 1.0

function M.augmentAllWins(allWins, onlyApp)
    if _axBlocked() then return end

    local appsToScan = {}
    if onlyApp then
        local appName = onlyApp:name() or ""
        if managedAllowed[appName] and onlyApp:kind() ~= -1 then
            appsToScan[1] = onlyApp
        end
    else
        local now = hs.timer.secondsSinceEpoch()
        if now - _lastFullAugment < FULL_AUGMENT_COOLDOWN then return end
        _lastFullAugment = now
        for _, app in ipairs(hs.application.runningApplications()) do
            local appName = app:name() or ""
            if managedAllowed[appName] and app:kind() ~= -1 then
                table.insert(appsToScan, app)
            end
        end
    end

    if #appsToScan == 0 then return end

    local tStart = hs.timer.secondsSinceEpoch()
    for _, fapp in ipairs(appsToScan) do
        local elapsed = hs.timer.secondsSinceEpoch() - tStart
        if elapsed >= 2.0 then
            -- Out of budget: remaining apps stay unscanned this pass.
            if profiler.enabled then
                profiler.log("augmentAllWins budget exhausted", elapsed)
            end
            return
        end
        local appName = fapp:name() or ""
        local t0 = hs.timer.secondsSinceEpoch()
        local appWins = fapp:allWindows()
        local dt = hs.timer.secondsSinceEpoch() - t0
        if dt >= AX_SLOW then
            -- AX is locked. Trip the breaker so every other path backs off too, instead of
            -- silently skipping this app and retrying on the next focus event.
            _axTrip(dt, appName)
            return
        end
        if dt >= 0.5 then
            -- Slow but under the trip threshold: skip, and say so — this app's windows stay
            -- unmanaged until it responds faster, which was previously silent.
            if profiler.enabled then
                profiler.log("augmentAllWins skip (slow app)", dt, appName)
            end
        else
            for _, w in ipairs(appWins) do
                local wid = w:id()
                if wid and wid > 0 and w:isStandard() and not w:isMinimized() then
                    if not _trackedWins[wid] then
                        _trackedWins[wid] = w
                        table.insert(allWins, w)
                    end
                    if not state.tags[wid] then
                        core.registerWindow(w)
                    end
                end
            end
        end
    end
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

    -- Re-evaluate floating classification after a window has had time to settle.
    -- isStandard() may return false during initial window creation, causing
    -- isFloating() to cache a false positive. Called 1s after windowCreated.
    function M._reevaluateFloating(captureId)
        return function()
            local w = _trackedWins[captureId]
            if w and state.tags[captureId] and core.isFloating(w) then
                if state.floatingOverrides[captureId] == nil then
                    core.invalidateFloatingCache(captureId)
                    if not core.isFloating(w) then
                        core.registerWindow(w)
                        layout.tile()
                    end
                end
            end
        end
    end

    filter:subscribe(hs.window.filter.windowCreated, profiler.wrap("wf:windowCreated", function(win)
        if _axBlocked() then return end
        if not win then return end

        local id = win:id()
        if not id or id == 0 then
            hs.timer.doAfter(0.1, function()
                local retryId = win:id()
                if retryId and retryId ~= 0 then
                    _trackedWins[retryId] = win
                    core.registerWindow(win)
                    layout.tile()
                    local captureId = retryId
                    hs.timer.doAfter(1.0, M._reevaluateFloating(captureId))
                end
            end)
            return
        end

        _trackedWins[id] = win
        core.registerWindow(win)
        layout.tile()
        local captureId = id
        hs.timer.doAfter(1.0, M._reevaluateFloating(captureId))
    end))

    -- =========================================================================
    -- WINDOW TITLE CHANGED
    -- =========================================================================
    filter:subscribe(hs.window.filter.windowTitleChanged, profiler.wrap("wf:titleChanged", function(win)
        if _axBlocked() then return end
        if not win or not win:id() or win:id() == 0 then return end
        core.invalidateFloatingCache(win:id())
        core.registerWindow(win)
        layout.tile()
    end))

    -- =========================================================================
    -- WINDOW DESTROYED
    -- =========================================================================
    filter:subscribe(hs.window.filter.windowDestroyed, profiler.wrap("wf:windowDestroyed", function(win)
        if _axBlocked() then return end
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
            -- Liveness is checked against the event-driven set, not by probing AX.
            -- This used to call hs.window(id), which costs ~37 ms for an id that no longer
            -- exists — i.e. on virtually every window close — and, far worse, a false
            -- "still exists" abandoned the cleanup permanently with no retry. That was a
            -- primary source of the hundreds of dead ids that accumulated in state.tags.
            -- _trackedWins[id] was set to nil at the top of this handler, so it is non-nil
            -- here only if a windowCreated/windowFocused event genuinely re-registered the
            -- window in the meantime — a stronger signal, for zero cost.
            -- If a live window is ever cleaned up in error it is self-healing: the next focus
            -- event or the 60s resync re-registers it via core.registerWindow().
            if _trackedWins[id] then
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
        if _axBlocked() then return end
        if not win then return end

        local id = win:id()
        if not id or id == 0 then return end

        local app = win:application()

        -- Register the focused window if it's not tracked.
        local needsTile = false
        local inTracked = (_trackedWins[id] ~= nil)
        local hasTag = (state.tags[id] ~= nil)
        if not inTracked or not hasTag then
            _trackedWins[id] = win
            core.registerWindow(win)
            local captureId = id
            hs.timer.doAfter(1.0, M._reevaluateFloating(captureId))
            needsTile = true
        end

        -- Scan the focused app for unmanaged sibling windows (e.g. Firefox tab-detach
        -- windows that the AXObserver filter didn't fire events for). Only trigger a
        -- full tile if we actually found something, to avoid re-raising
        -- floating windows on every focus click.
        -- Scoped to `app`: the all-apps sweep belongs on the 60s resync, not here.
        local scanWins = {}
        M.augmentAllWins(scanWins, app)
        if #scanWins > 0 then
            needsTile = true
        end

        if needsTile then
            -- Always tile. layout.tile() is debounced by perfProfile().tileDelay, so repeated
            -- calls coalesce by themselves. The `>= tileProtectionWindow` test that used to
            -- guard this did not defer the tile, it DROPPED it — so a window registered within
            -- 0.5 s of any other tile never got laid out. That is a second, independent route
            -- to the same "first window after a tag switch or wake isn't tiled" symptom as the
            -- winMap staleness fixed in section 10.
            layout.tile()
        end

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

        -- Anti-jump protection for cross-tag focus.
        --
        -- state.launching belongs here rather than at the top of the handler. Its purpose is to
        -- avoid reacting to focus stolen by an app we just launched; applied to the whole
        -- handler it also skipped window registration and the state.tagLastFocused bookkeeping
        -- below for 2 s after every Alt+Return, leaving a stale "last focused" id that later
        -- tag switches then restore focus to.
        if state.launching then return end

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
        if _axBlocked() then return end
        if not win or not win:id() or win:id() == 0 then return end

        local tag = state.special.active and state.special.tag or state.currentTag
        if not core.isFloating(win) and not state.isTagFree(tag) then
            resizeWatcher:start()
        end
    end))

    -- Populate _trackedWins at startup, then resync every 60s to catch any drift.
    _resync()
    hs.timer.new(60, _resync):start()

    -- Allow newly launched apps into the filter; trigger a deferred resync for new apps.
    -- There is deliberately no appActivated hook: app:allWindows() on every Slack activation
    -- caused 25 s freezes when the AX lock was held. The 60s _resync() covers those windows.
    _appWatcher = hs.application.watcher.new(function(appName, event, app)
        if event == hs.application.watcher.launched then
            -- Adopt the handle directly so the 1s scanner doesn't wait out FF_LOOKUP_BACKOFF
            -- (and doesn't pay for a lookup it can get for free here).
            if appName == "Firefox" then
                _ffApp = app
                _ffLookupAt = 0
            end
            if _shouldAllow(app) then filter:allowApp(appName) end
            if managedAllowed[appName] then
                hs.timer.doAfter(1.5, _resync)
            end
        end
    end)
    _appWatcher:start()

    -- After any detected freeze >= 5 s, extend the AX suppress guard for 90 s.
    -- Only overrides the current timer when the new deadline would be later, so
    -- the caffeinate watcher's 300 s wake:suppress is never shortened to 90 s.
    -- A genuine stall (the profiler now discriminates sleep from blocking via the monotonic
    -- clock, so this only fires for real ones). Suppress, but probe out of it rather than
    -- sitting out a fixed backoff.
    profiler.onFreeze = function(gap)
        _suppressUntilHealthy(string.format("post-freeze %.0fs", gap), AX_BACKOFF)
    end

    -- Suppress AX callbacks after wake, then lift as soon as a probe says AX is answering
    -- (ceiling WAKE_SUPPRESS_MAX). Anything still locked trips the breaker instead.
    -- _cafWatcher must be module-level — Hammerspoon GCs watchers without a live reference.
    _cafWatcher = hs.caffeinate.watcher.new(function(event)
        if event == hs.caffeinate.watcher.systemWillSleep then
            profiler.resetHeartbeat()
        elseif event == hs.caffeinate.watcher.systemDidWake then
            profiler.resetHeartbeat()

            -- Probe BEFORE suppressing anything. If AX answers immediately — which is the
            -- normal case, ~0.1 ms — there is nothing to protect against, so window events
            -- keep flowing uninterrupted and this costs one sub-millisecond read.
            -- Suppression therefore only ever engages on evidence that AX is actually stuck,
            -- rather than on the assumption that it might be.
            profiler.lastEvent = "wake"
            if _axProbeHealthy() then
                -- Direct evidence that AX answers. Clear anything a freeze detection armed —
                -- a lock/unlock used to leave a 90 s post-freeze suppression in place even
                -- though this probe had just proved AX was fine.
                if _wakeSuppress then
                    _liftSuppress("wake probe ok")
                else
                    profiler.log("wake: AX healthy, no suppression", 0)
                    _resync()
                    layout.tile()
                end
                return
            end
            _suppressUntilHealthy("wake", WAKE_SUPPRESS_MAX)
        end
    end)
    _cafWatcher:start()

    -- Firefox-specific scanner. Tab-detach windows are often invisible to the AXObserver
    -- filter, so a dedicated scan bridges the gap. Interval raised from 1 s to 3 s: each tick
    -- costs an allWindows() (~1.8 ms measured) and a wakeup, forever, for a case that a
    -- 1 s cadence never justified -- windowCreated and the 60 s resync also cover it.
    M._ffScanTimer = hs.timer.new(3.0, function()
        if _axBlocked() then return end

        -- Resolve Firefox via the cache; see FF_LOOKUP_BACKOFF above for why.
        if _ffApp and not _ffApp:isRunning() then _ffApp = nil end
        if not _ffApp then
            local lookupNow = hs.timer.secondsSinceEpoch()
            if lookupNow - _ffLookupAt < FF_LOOKUP_BACKOFF then return end
            _ffLookupAt = lookupNow
            _ffApp = hs.application.get("Firefox")
            if not _ffApp then return end
        end
        local ff = _ffApp

        local _t0 = hs.timer.secondsSinceEpoch()
        local appWins = ff:allWindows()
        local _dt = hs.timer.secondsSinceEpoch() - _t0
        if _dt >= AX_SLOW then
            -- Once per second is the worst possible cadence to keep retrying under a lock.
            _axTrip(_dt, "Firefox")
            return
        end
        local foundNew = false
        for _, w in ipairs(appWins) do
            local wid = w:id()
            if wid and wid > 0 and w:isStandard() and not w:isMinimized() then
                if not _trackedWins[wid] then
                    _trackedWins[wid] = w
                    foundNew = true
                end
                if not state.tags[wid] then
                    core.registerWindow(w)
                    foundNew = true
                end
            end
        end
        if foundNew then
            layout.tile()
        end
    end):start()
end

return M
