-- =============================================================================
-- NanoWM Profiler - Temporary slowness investigation
-- Set M.enabled = false (or remove require calls) when done investigating.
-- Log file: ~/.hammerspoon/nanowm_slow.log
-- =============================================================================

local M = {}

M.enabled = true

-- Log ops slower than this (seconds). os.execute/hs.execute are logged always.
M.threshold = 0.030

local LOG = os.getenv("HOME") .. "/.hammerspoon/nanowm_slow.log"
local _fh = nil
local _lineCount = 0
local MAX_LINES = 8000

local function openLog()
    _fh = io.open(LOG, "a")
end

local function writeLog(msg)
    if not _fh then openLog() end
    if _fh then
        _fh:write(msg .. "\n")
        _fh:flush()
        _lineCount = _lineCount + 1
        if _lineCount >= MAX_LINES then
            -- Rotate: truncate and restart
            _fh:close()
            _fh = io.open(LOG, "w")
            if _fh then
                _fh:write(string.format("-- rotated at %s (was %d lines)\n",
                    os.date("%Y-%m-%d %H:%M:%S"), MAX_LINES))
            end
            _lineCount = 1
        end
    end
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

-- Wrap a function: times every call, logs if >= threshold.
-- Handles up to 4 return values (enough for all NanoWM callbacks).
function M.wrap(name, fn)
    if not M.enabled then return fn end
    return function(...)
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
function M.patchGlobals()
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

-- Start a 1-second heartbeat. Only logs when there is a gap > 2s (i.e. a real freeze).
-- Call once from init.lua after profiler is enabled.
local _heartbeatTimer = nil
function M.startHeartbeat()
    local _lastBeat = hs.timer.secondsSinceEpoch()
    _heartbeatTimer = hs.timer.new(1.0, function()
        local now = hs.timer.secondsSinceEpoch()
        local gap = now - _lastBeat
        if gap >= 2.0 then
            M.log("*** FREEZE ***", gap, string.format("Hammerspoon was frozen for %.1fs", gap))
        end
        _lastBeat = now
    end)
    _heartbeatTimer:start()
end

return M
