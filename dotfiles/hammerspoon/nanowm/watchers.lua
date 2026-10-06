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
    ["Activity Monitor"] = true, Alacritty = true, Arc = true, Ghostty = true,
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

local _inputTap  -- defined with the cross-tag focus policy below

-- True while the screen is locked (or the session is off the console). App windows can't be
-- enumerated then: at wake, before unlock, app:allWindows() returned nothing for every managed
-- app while hs.window.allWindows() still listed ~11 system windows (measured). The same holds
-- in the dark wakes of a closed laptop, when overdue timers fire -- which is how two prune
-- sweeps overnight saw every window as dead and dropped all tags.
local function _sessionLocked()
    local p = hs.caffeinate.sessionProperties()
    if not p then return false end
    local locked = p.CGSSessionScreenIsLocked
    return locked == true or locked == 1 or p.kCGSSessionOnConsoleKey == false
end
M.sessionLocked = _sessionLocked

local function _resync()
    -- macOS disables an event tap whose callback ever times out; re-arm it.
    if _inputTap and not _inputTap:isEnabled() then _inputTap:start() end
    if _axBlocked() then return end
    -- Locked: the enumeration below would come back empty and wipe _trackedWins (the wake
    -- handler runs this at systemDidWake, before unlock). screensDidUnlock resyncs instead.
    if _sessionLocked() then return end
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
    -- Second line of defence behind the lock check: an enumeration that finds nothing at all
    -- is not evidence that every window closed (destroy events remove those individually), so
    -- it must not wipe the tracked set the prune sweep relies on.
    if next(fresh) ~= nil then
        _trackedWins = fresh
    end

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
--- App and caffeinate watchers — must be module-level to avoid GC after M.setup() returns
local _appWatcher = nil
local _cafWatcher = nil
local _vicFilter = nil
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

-- Tracked window by id, without AX calls. Use this instead of hs.window(id), which enumerates
-- every window of every app (hs.window.find -> allWindows) before comparing ids.
function M.getTrackedWindow(id)
    return id and _trackedWins[id] or nil
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

-- =============================================================================
-- Cross-tag focus policy
-- =============================================================================
-- macOS moves focus on its own all the time: closing a window hands key status to the app's
-- next window, quitting or hiding an app activates the next app, apps activate themselves.
-- Whenever that lands on a window parked on another tag, following it is a "random" tag jump,
-- and NOT following it (the old protection-window early returns) leaves keyboard focus on an
-- invisible window. Both were observed: closing a Firefox window on tag 8 jumped to tag 9, or,
-- when a tile had just run, silently focused the tag-9 window in its parked corner.
--
-- Policy: focus never leaves the current tag unless the user asked for it. Accepted intents:
--   * Vicinae  - panel open or just closed (extension activating a window/tab)
--   * Dock     - a click on a Dock item
--   * Cmd-Tab  - the macOS app switcher
--   * link     - a browser activated from another app right after user input (clicked link)
-- Anything else marks the window's tag urgent and pulls focus back to the current tag's most
-- recently used window, or the desktop when the tag is empty.
--
-- The decision is deferred ~0.2 s (_scheduleResolve) so the app activation that caused a focus
-- change is seen first, and so a burst of focus events collapses into one decision.

local DECISION_DELAY   = 0.2
local CMD_TAB_WINDOW   = 1.0   -- activation within this long after Cmd-Tab release
local DOCK_WINDOW      = 1.5   -- ... after a Dock item click
local LINK_WINDOW      = 2.0   -- browser activation this soon after an activation from another app
local INPUT_WINDOW     = 3.0   -- ... and this soon after a click or key press
local FALLTHROUGH_WIN  = 1.0   -- focus changes this soon after a close/quit/hide are the OS's doing
local LAUNCH_WINDOW    = 10.0  -- a window of an app launched via core.launchApp this soon after
local HISTORY_MAX      = 16

local _cmdTabArmed = false
local _cmdTabAt = 0
local _dockClickAt = 0
local _lastInputAt = 0
local _fallthroughAt = 0
local _frontApp = nil
local _lastActivation = { app = nil, prev = nil, t = 0 }

-- Per-tag focus history, most recent first. Volatile: state.tagLastFocused is the persisted
-- fallback after a reload.
local _focusHistory = {}
local _pushedAt = {}  -- id -> when it last became the head of its tag's history

local function _pushHistory(tag, id)
    local list = _focusHistory[tag]
    if not list then
        list = {}
        _focusHistory[tag] = list
    end
    if list[1] == id then return end
    for i = #list, 1, -1 do
        if list[i] == id then table.remove(list, i) end
    end
    table.insert(list, 1, id)
    _pushedAt[id] = hs.timer.secondsSinceEpoch()
    if #list > HISTORY_MAX then list[#list] = nil end
end

local function _dropHistory(id)
    _pushedAt[id] = nil
    for _, list in pairs(_focusHistory) do
        for i = #list, 1, -1 do
            if list[i] == id then table.remove(list, i) end
        end
    end
end

-- Did the window `id` (being destroyed) hold focus on `tag`? Either it heads the history, or the
-- focus event for macOS's replacement pick arrived before the destroy event and pushed that
-- pick on top of it a moment ago. In the second case the pick is demoted below the tag's
-- previous window, so the close-triggered resolve re-picks from the user's own history.
local function _heldFocus(tag, id, now)
    local list = _focusHistory[tag]
    if not list then return false end
    if list[1] == id then return true end
    if list[2] == id and now - (_pushedAt[list[1]] or 0) < FALLTHROUGH_WIN then
        local pick = table.remove(list, 1)
        -- After the closed window's successor; clamped, table.insert rejects gaps.
        table.insert(list, math.min(3, #list + 1), pick)
        return true
    end
    return false
end

-- Most recently focused window that is still alive, still on `tag`, and not hidden/minimized.
local function _mruWindow(tag)
    local function usable(id)
        local w = id and _trackedWins[id]
        if w and state.tags[id] == tag and w:isVisible() then return w end
        return nil
    end
    for _, id in ipairs(_focusHistory[tag] or {}) do
        local w = usable(id)
        if w then return w end
    end
    return usable(state.tagLastFocused[tag])
end

local function _vicinaeActive(now)
    return (state.vicinaePanelCount or 0) > 0
        or (now - (state.vicinaePanelClosedAt or 0)) < 1.5
end

-- True when `win` belongs to the app just launched via core.launchApp (e.g. Slack from the leader).
local function _isLaunchTarget(win, now)
    local li = state.launchIntent
    if not (li and win and now - li.t < LAUNCH_WINDOW) then return false end
    local app = win:application()
    return app ~= nil and app:name() == li.app
end

-- Why the user wants focus to follow `win` to its tag, or nil when nobody asked for it.
local function _crossTagIntent(win, now)
    -- Right after the focused window/app closed, macOS picks the next focus itself. Only input
    -- that came after the close counts then: Vicinae/Dock/Cmd-Tab state left over from quitting
    -- an app through Vicinae or the Dock menu is not a request to jump to macOS's pick.
    if _cmdTabAt > _fallthroughAt and now - _cmdTabAt < CMD_TAB_WINDOW then return "Cmd-Tab" end
    if _dockClickAt > _fallthroughAt and now - _dockClickAt < DOCK_WINDOW then return "Dock" end
    if _isLaunchTarget(win, now) and state.launchIntent.t > _fallthroughAt then return "launch" end

    -- A link opened from another app looks like: browser activated from a different app, with
    -- recent user input. Closing the last window of an app looks the same (Cmd+W is input too,
    -- and macOS then activates whatever is next, often the browser), hence the fallthrough guard.
    if now - _fallthroughAt < FALLTHROUGH_WIN then return nil end
    if _vicinaeActive(now) then return "Vicinae" end
    local app = win:application()
    local appName = app and app:name() or ""
    if config.browserApps[appName]
        and _lastActivation.app == appName
        and _lastActivation.prev ~= appName
        and now - _lastActivation.t < LINK_WINDOW
        and now - _lastInputAt < INPUT_WINDOW then
        return "link"
    end
    return nil
end

local function _followToTag(tag, win, why)
    local app = win:application()
    print(string.format("[NanoWM] Cross-tag focus (%s): %s -> tag %s",
        why, app and app:name() or "?", tostring(tag)))
    -- A launch intent is good for one follow; later focus changes of that app are judged afresh.
    if why == "launch" then state.launchIntent = nil end
    -- gotoTag focuses tagLastFocused[tag] after a short delay; point it at this window so
    -- that refocus agrees with ours instead of racing it.
    state.tagLastFocused[tag] = win:id()
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
    if state.focusTimer then
        state.focusTimer:stop()
        state.focusTimer = nil
    end
end

-- Focus the context tag's MRU window, or the desktop if the tag is empty. Streak-limited so an
-- app that keeps re-grabbing focus produces a little flicker, not a focus fight.
local _pullBackAt = 0
local _pullBackStreak = 0

local function _focusContextTag(ctx)
    local now = hs.timer.secondsSinceEpoch()
    if now - _pullBackAt < 2.0 then
        _pullBackStreak = _pullBackStreak + 1
    else
        _pullBackStreak = 1
    end
    _pullBackAt = now
    if _pullBackStreak > 3 then
        print("[NanoWM] Focus keeps leaving tag " .. tostring(ctx) .. ", giving up refocusing")
        return
    end

    local target = _mruWindow(ctx)
    if not target then
        target = core.getTiledWindows(ctx)[1]
    end
    if target then
        target:focus()
    else
        local desktop = hs.window.desktop()
        if desktop then desktop:focus() end
    end
end

local _resolveTimer = nil
local _resolveClose = false
local _resolveRetries = 0
local _resolveFocus

-- afterClose: a window/app that may have held focus on the current tag went away, so
-- re-pick focus from the tag's history even if macOS left it somewhere on-tag.
local function _scheduleResolve(afterClose, delay)
    if afterClose then _resolveClose = true end
    if not delay then _resolveRetries = 0 end
    if _resolveTimer then _resolveTimer:stop() end
    _resolveTimer = hs.timer.doAfter(delay or DECISION_DELAY, _resolveFocus)
end

_resolveFocus = function()
    _resolveTimer = nil
    if _axBlocked() then
        _resolveClose = false
        return
    end
    local now = hs.timer.secondsSinceEpoch()
    local ctx = state.special.active and state.special.tag or state.currentTag
    local win = hs.window.focusedWindow()

    -- Apps launched by nanowm briefly focus an existing window before their new one appears.
    -- Not so for a launch intent (core.launchApp): there the existing window is the target, and
    -- waiting out state.launching (2 s) made Leader -> a -> s take ~3 s to switch tags.
    if state.launching and not _isLaunchTarget(win, now) then
        _scheduleResolve(false, 0.3)
        return
    end
    local id = win and win:id()
    local tag = id and state.tags[id]

    -- Right at activation the app's key window may not be known yet (e.g. Firefox focusing a
    -- specific tab's window). Give it a moment before deciding there is nothing to do.
    if not tag and not _resolveClose and _resolveRetries < 3 then
        _resolveRetries = _resolveRetries + 1
        _scheduleResolve(false, DECISION_DELAY)
        return
    end
    local afterClose = _resolveClose
    _resolveClose = false

    -- PiP windows are shown on every tag (core.classifyWindow), so they are never off-tag.
    local offTag = tag and tag ~= ctx and tag ~= state.currentTag and not state.sticky[id]
        and win:title() ~= "Picture-in-Picture"

    if offTag and not core.isParked(win, id) then
        -- On another tag but on-screen: an active tag on another monitor. Following it changes
        -- nothing visually, so keep the old behaviour, protections included.
        if now - state.lastTileTime < config.tileProtectionWindow then return end
        if now - state.lastManualTagSwitch < config.tagSwitchCooldown then return end
        _followToTag(tag, win, "other monitor")
        return
    end

    if offTag then
        -- The cooldown stops focus events from the tag just left (still arriving while a switch
        -- settles) from following straight back, e.g. after a Vicinae-driven tag switch. Focus
        -- shuffled by our own switch (incl. gotoTag activating Finder on an empty tag) isn't
        -- news either, so it doesn't mark the tag urgent.
        local settling = now - state.lastManualTagSwitch < config.tagSwitchCooldown
        local why = _crossTagIntent(win, now)
        if why and not settling then
            _followToTag(tag, win, why)
            return
        end
        local app = win:application()
        print(string.format("[NanoWM] Cross-tag focus blocked: %s (tag %s), staying on tag %s",
            app and app:name() or "?", tostring(tag), tostring(ctx)))
        if not settling then tags.markTagUrgent(tag) end
        _focusContextTag(ctx)
        return
    end

    if afterClose then
        local target = _mruWindow(ctx)
        if target and target:id() ~= id then
            target:focus()
        end
    end
end

local function _clickOnDockItem(pos)
    if _axBlocked() then return false end
    local ok, role = pcall(function()
        local el = hs.axuielement.systemElementAtPosition(pos)
        return el and el:attributeValue("AXRole")
    end)
    return ok and role == "AXDockItem"
end

-- Cheap input bookkeeping for _crossTagIntent. The callback runs on every key press and click,
-- so it only records timestamps; the one AX call (Dock hit test) is deferred off the tap.
local function _startInputTap()
    local types = hs.eventtap.event.types
    local tabKey = hs.keycodes.map.tab
    _inputTap = hs.eventtap.new({ types.keyDown, types.flagsChanged, types.leftMouseDown }, function(e)
        local t = e:getType()
        local now = hs.timer.secondsSinceEpoch()
        if t == types.keyDown then
            _lastInputAt = now
            if e:getKeyCode() == tabKey and e:getFlags().cmd then _cmdTabArmed = true end
        elseif t == types.flagsChanged then
            if _cmdTabArmed and not e:getFlags().cmd then
                _cmdTabArmed = false
                _cmdTabAt = now
            end
        else
            _lastInputAt = now
            if core.isMouseInDockArea() then
                local pos = e:location()
                hs.timer.doAfter(0, function()
                    if _clickOnDockItem(pos) then _dockClickAt = now end
                end)
            end
        end
        return false
    end)
    _inputTap:start()
end

-- App activation (cmd-tab, Dock, link, an app activating itself, or macOS activating the next
-- app after a quit). Cheap: no window enumeration. Records the activation for the link
-- heuristic, then lets the resolver decide.
function M.followActivatedApp(app, appName)
    if not app then return end
    _lastActivation = { app = appName, prev = _frontApp, t = hs.timer.secondsSinceEpoch() }
    _frontApp = appName
    _scheduleResolve(false)
end

-- A Vicinae browser command (Search Browser Tabs) activates a tab in a
-- browser window that may live on another tag. Firefox/Chrome request window
-- focus, but macOS does not raise a window nanowm parked off-screen, so no
-- focus or activation event ever fires — the only observable signal is the
-- browser window's title changing.
--
-- Note the browser is usually NOT the frontmost app here: the launcher is a
-- non-activating panel, so opening it over some other app leaves that app
-- frontmost, and the extension's focus request does not change that. The
-- discriminator is therefore the panel state: background tab title updates
-- (YouTube autoplay in a parked window, unread counters) happen without the
-- panel, and while the panel is showing the user is deliberately acting on
-- the browser.
function M.followTabActivation(win)
    local app = win:application()
    local appName = app and app:name() or ""
    if not config.browserApps[appName] then return end

    local id = win:id()
    local tag = state.tags[id]
    if not tag or tag == state.currentTag then return end
    if state.special.active and tag == state.special.tag then return end
    if core.isFloating(win) then return end

    -- If the window actually became the global key window, the windowFocused
    -- / followActivatedApp paths already handled (or deliberately declined) it.
    local frontmost = hs.application.frontmostApplication()
    if frontmost then
        local focused = frontmost:focusedWindow()
        if focused and focused:id() == id then return end
    end

    local now = hs.timer.secondsSinceEpoch()
    if now - state.lastTileTime < config.tileProtectionWindow then return end
    if now - state.lastManualTagSwitch < config.tagSwitchCooldown then return end

    local panelShowing = (state.vicinaePanelCount or 0) > 0
        or (now - (state.vicinaePanelClosedAt or 0)) < 1.5
    if not panelShowing then return end

    print(string.format("[NanoWM] Tab activated in %s window on tag %s (Vicinae panel), switching",
        appName, tostring(tag)))

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
end

function M.setup()
    M.updateScreenFrames()
    screenWatcher = hs.screen.watcher.new(function()
        M.updateScreenFrames()
        if not _wakeSuppress then layout.tile() end
        tags.updateBorder()  -- the special-tag border follows its screen
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
        M.followTabActivation(win)
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

        -- macOS is about to hand focus to whatever it picks next (often this app's window on
        -- another tag). If this window held focus on the current tag, re-pick from the tag's
        -- history instead. Closing an unfocused window moves no focus, so it is not a fallthrough.
        local now = hs.timer.secondsSinceEpoch()
        local ctx = state.special.active and state.special.tag or state.currentTag
        local wasFocused = tag ~= nil and tag == ctx and _heldFocus(ctx, id, now)
        _dropHistory(id)
        if wasFocused then
            _fallthroughAt = now
            _scheduleResolve(true)
        end

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

        -- The special-tag backdrop fades out while a non-special window has focus.
        if state.special.active then tags.updateBorder() end

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

        -- While a close-triggered resolve is pending, this focus is macOS's replacement pick,
        -- not the user's: recording it would make it the "most recent" window the resolve then
        -- dutifully keeps.
        if tag and not _resolveClose then
            state.tagLastFocused[tag] = id
            _pushHistory(tag, id)
        end

        -- If it's a window on the current tag (or special), and it's tiled, we might need to re-tile (for scrolling layout)
        local currentContextTag = state.special.active and state.special.tag or state.currentTag
        if tag == currentContextTag then
            if not core.isFloating(win) then
                if state.getLayout(tag) == "scrolling" then
                    layout.tile()
                end
                return
            end
            -- Same guards as before the cross-tag policy moved out of this handler: don't
            -- react to focus stolen by an app we just launched or shuffled by a tile/switch.
            local now = hs.timer.secondsSinceEpoch()
            if state.launching
                or now - state.lastTileTime < config.tileProtectionWindow
                or now - state.lastManualTagSwitch < config.tagSwitchCooldown then
                return
            end
            win:raise()
            integrations.updateSketchybar()
            return
        end

        if not tag or tag == state.currentTag then
            return
        end

        -- Cross-tag focus. Extensions can focus hidden windows of an ALREADY frontmost app (the
        -- Vicinae browser extension focusing a tab whose window lives on another tag) with no
        -- application activation, so this event is the only signal for those. Whether to
        -- follow or pull focus back is the resolver's call; see "Cross-tag focus policy".
        _scheduleResolve(false)
    end))

    -- =========================================================================
    -- WINDOW MOVED (for resize detection)
    -- =========================================================================
    filter:subscribe(hs.window.filter.windowMoved, profiler.wrap("wf:windowMoved", function(win)
        if _axBlocked() then return end
        if not win or not win:id() or win:id() == 0 then return end

        -- Keep the backdrop's hole on a special window that was moved or resized.
        if state.special.active and state.tags[win:id()] == state.special.tag then
            tags.updateBorder()
        end

        local tag = state.special.active and state.special.tag or state.currentTag
        if not core.isFloating(win) and not state.isTagFree(tag) then
            resizeWatcher:start()
        end
    end))

    -- Populate _trackedWins at startup, then resync every 60s to catch any drift.
    _resync()
    -- Anchored: an unreferenced hs.timer is garbage-collected and silently stops firing.
    M._resyncTimer = hs.timer.new(60, _resync):start()

    -- Allow newly launched apps into the filter; trigger a deferred resync for new apps.
    -- There is deliberately no window enumeration on activation: app:allWindows() on every
    -- Slack activation caused 25 s freezes when the AX lock was held. The 60s _resync()
    -- covers those windows. Activation events are still observed, but they only drive
    -- M.followActivatedApp (cheap: no window enumeration), which lets tags follow
    -- extension-driven app activations such as a browser extension focusing a tab.
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
        elseif event == hs.application.watcher.activated then
            M.followActivatedApp(app, appName)
        elseif event == hs.application.watcher.terminated
            or event == hs.application.watcher.hidden then
            -- macOS activates the next app; if it is parked on another tag that is not a
            -- jump the user asked for. afterClose re-picks focus if this app held it.
            -- Only a frontmost app hands focus on: a background app quitting or hiding moves no
            -- focus, and re-picking then yanked focus out of whatever the user was typing in.
            -- The next app's activation can arrive before this event, hence the prev check.
            local now = hs.timer.secondsSinceEpoch()
            local wasFront = _frontApp == appName
                or (_lastActivation.prev == appName and now - _lastActivation.t < FALLTHROUGH_WIN)
            if _frontApp == appName then _frontApp = nil end
            if wasFront then
                _fallthroughAt = now
                _scheduleResolve(true)
            end
        end
    end)
    _appWatcher:start()

    _startInputTap()
    -- Seed the frontmost app: it is otherwise only learned from activation events, so right
    -- after a reload a quit of the current app would not count as frontmost.
    do
        local front = hs.application.frontmostApplication()
        _frontApp = front and front:name() or nil
    end

    -- Track Vicinae panel visibility by counting its windows. The panel is a
    -- non-activating NSPanel (0 windows when hidden, 3 when shown) and fires
    -- no application-activation events, so this is how followTabActivation
    -- knows the user is interacting with the launcher. Seeded once in case the
    -- panel is already open; drift is corrected on the next create/destroy.
    _vicFilter = hs.window.filter.new("Vicinae")
    _vicFilter:subscribe(hs.window.filter.windowCreated, function()
        state.vicinaePanelCount = (state.vicinaePanelCount or 0) + 1
    end)
    _vicFilter:subscribe(hs.window.filter.windowDestroyed, function()
        state.vicinaePanelCount = math.max(0, (state.vicinaePanelCount or 0) - 1)
        state.vicinaePanelClosedAt = hs.timer.secondsSinceEpoch()
    end)
    do
        local vic = hs.application.get("Vicinae")
        state.vicinaePanelCount = vic and #vic:allWindows() or 0
    end

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
        if event == hs.caffeinate.watcher.screensDidUnlock then
            -- App windows are enumerable again; _resync skipped while locked.
            if not _axBlocked() then
                _resync()
                layout.tile()
            end
        elseif event == hs.caffeinate.watcher.systemWillSleep then
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
