-- =============================================================================
-- NanoWM Profiler - Opt-in slowness investigation
--
-- Disabled by default: when enabled it patches os.execute/hs.execute process-wide
-- and writes to disk, which adds main-thread overhead to the hot path it measures.
--
-- Enable from the Hammerspoon console:
--     hs.settings.set("nanowm_profiler", true);  hs.reload()
-- Disable again with:
--     hs.settings.set("nanowm_profiler", false); hs.reload()
--
-- Log file: ~/.hammerspoon/nanowm_slow.log (file output only while enabled;
-- rare events such as "AX circuit open" always reach the HS console).
-- =============================================================================

local M = {}

M.enabled = hs.settings.get("nanowm_profiler") == true

-- Log ops slower than this (seconds). os.execute/hs.execute are logged always.
M.threshold = 0.030

local function _home()
    local h = os.getenv("HOME") or ""
    if h:match("^/Users/") then return h end
    return "/Users/" .. (os.getenv("USER") or "gentooway")
end
local LOG = _home() .. "/.hammerspoon/nanowm_slow.log"
local _fh = nil
local _lineCount = 0
local MAX_LINES = 8000

-- Lines are buffered and written in batches: flushing per line put a synchronous
-- disk write on the main event loop for every logged call.
local _buf = {}
local _bufTimer = nil
local FLUSH_INTERVAL = 5.0   -- seconds
local MAX_BUFFERED = 200     -- force a flush before the buffer grows past this

local flush -- forward declaration (referenced by the flush timer)

local function countLines()
    local f = io.open(LOG, "r")
    if not f then return 0 end
    local n = 0
    for _ in f:lines() do n = n + 1 end
    f:close()
    return n
end

local function openLog()
    _lineCount = countLines()
    _fh = io.open(LOG, "a")
end

local function rotate()
    if _fh then _fh:close() end
    _fh = io.open(LOG, "w")
    if _fh then
        _fh:write(string.format("-- rotated at %s (was %d lines)\n",
            os.date("%Y-%m-%d %H:%M:%S"), _lineCount))
        _fh:flush()
    end
    _lineCount = 1
end

flush = function()
    if _bufTimer then
        _bufTimer:stop()
        _bufTimer = nil
    end
    if #_buf == 0 then return end
    if not _fh then openLog() end
    if not _fh then
        _buf = {}
        return
    end
    _fh:write(table.concat(_buf, "\n") .. "\n")
    _fh:flush()  -- one flush per batch, not per line
    _lineCount = _lineCount + #_buf
    _buf = {}
    if _lineCount >= MAX_LINES then rotate() end
end

-- Force any buffered lines to disk. Safe to call when disabled (no-op).
M.flush = flush

local function writeLog(msg)
    if not M.enabled then return end
    _buf[#_buf + 1] = msg
    if #_buf >= MAX_BUFFERED then
        flush()
    elseif not _bufTimer then
        _bufTimer = hs.timer.doAfter(FLUSH_INTERVAL, flush)
    end
end

-- Don't lose the tail of a profiling session on reload/quit — that is exactly
-- the window of interest when diagnosing a freeze. Chain rather than replace.
local _prevShutdown = hs.shutdownCallback
hs.shutdownCallback = function()
    flush()
    if _prevShutdown then _prevShutdown() end
end

function M.log(name, elapsed, extra)
    local ms = elapsed * 1000
    local ts = os.date("%H:%M:%S")
    local msg
    if extra then
        msg = string.format("[%s] %6.1fms  %-35s  %s", ts, ms, name, extra)
    else
        msg = string.format("[%s] %6.1fms  %s", ts, ms, name)
    end
    print("[prof] " .. msg)
    writeLog(msg)
end

-- Wrap a function: stamps lastEvent + times every call, logs if >= threshold.
-- Handles up to 4 return values (enough for all NanoWM callbacks).
function M.wrap(name, fn)
    if not M.enabled then return fn end
    return function(...)
        M.lastCallback = name
        M.lastEvent = name
        local t0 = hs.timer.secondsSinceEpoch()
        local ok, a, b, c, d = pcall(fn, ...)
        local dt = hs.timer.secondsSinceEpoch() - t0
        if dt >= M.threshold then M.log(name, dt) end
        if not ok then error(a, 2) end
        return a, b, c, d
    end
end

-- Stash originals so we can unpatch later
local _origOsExec  = os.execute
local _origHsExec  = hs.execute

-- Patch os.execute and hs.execute globally.
-- Every call is logged because both functions always block the event loop.
-- No-op unless profiling is enabled: this rewrites globals for ALL Hammerspoon
-- code (AClock, VimMode, the caps-lock watcher, ...), not just NanoWM.
function M.patchGlobals()
    if not M.enabled then return end

    os.execute = function(cmd)
        local t0 = hs.timer.secondsSinceEpoch()
        local r = _origOsExec(cmd)
        local dt = hs.timer.secondsSinceEpoch() - t0
        M.log("os.execute", dt, (cmd or ""):sub(1, 80))
        return r
    end

    hs.execute = function(cmd, ...)
        local t0 = hs.timer.secondsSinceEpoch()
        local r1, r2, r3 = _origHsExec(cmd, ...)
        local dt = hs.timer.secondsSinceEpoch() - t0
        M.log("hs.execute", dt, (cmd or ""):sub(1, 80))
        return r1, r2, r3
    end
end

function M.unpatchGlobals()
    os.execute = _origOsExec
    hs.execute = _origHsExec
end

-- Breadcrumbs for freeze diagnosis.
-- lastCallback: set by M.wrap() at the START of every AXObserver callback (never overwritten by AX calls).
-- lastEvent: set just before each blocking AX call (resync:appName, appActivated:appName, etc.).
-- After a freeze: lastCallback identifies the triggering event; lastEvent identifies the AX call.
M.lastCallback = "startup"
M.lastEvent = "startup"

-- Optional callback fired after any detected freeze >= 5 s.
-- Set by watchers.lua to extend the wake-suppress guard after an unexpected freeze.
M.onFreeze = nil

-- Start a 1-second heartbeat. Only logs when there is a gap > 2s (i.e. a real freeze).
-- Call once from init.lua after profiler is enabled.
local _heartbeatTimer = nil
local _resetHeartbeat = nil

-- Call on systemWillSleep/systemDidWake so the sleep duration itself isn't
-- logged as a freeze (all timers, including this heartbeat, pause during sleep).
function M.resetHeartbeat()
    if _resetHeartbeat then _resetHeartbeat() end
end

function M.startHeartbeat()
    if not M.enabled then return end

    local _lastBeat = hs.timer.secondsSinceEpoch()
    _resetHeartbeat = function() _lastBeat = hs.timer.secondsSinceEpoch() end
    _heartbeatTimer = hs.timer.new(1.0, function()
        local now = hs.timer.secondsSinceEpoch()
        local gap = now - _lastBeat
        if gap >= 2.0 then
            -- Collect running UI apps (kind != -1) to help identify the AX culprit
            local apps = {}
            for _, app in ipairs(hs.application.runningApplications()) do
                if app:kind() ~= -1 then
                    local n = app:name()
                    if n then table.insert(apps, n) end
                end
            end
            table.sort(apps)
            local appList = table.concat(apps, ", ")
            M.log("*** FREEZE ***", gap,
                string.format("%.1fs | lastCallback: %s | lastEvent: %s | running: %s",
                    gap, M.lastCallback, M.lastEvent, appList))
            if gap >= 5.0 and M.onFreeze then
                M.onFreeze(gap)
            end
        end
        _lastBeat = now
    end)
    _heartbeatTimer:start()
end

return M
