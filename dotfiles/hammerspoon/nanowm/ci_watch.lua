-- Filesystem events are hints; the packaged observer validates records/results.
local M = {}
local state = {generation=0, running=false, pending=false}
local home = os.getenv('HOME') or ''
local marker = home .. '/.config/local-ci-status/enabled'
local configPath = home .. '/.config/local-ci-status/config.json'
local request

local function enabled()
    return hs.fs.attributes(marker, 'mode') == 'file'
end

local function advisory()
    hs.printf('[local-ci-status] observer unavailable (advisory)')
end

local function stopResource(name)
    if state[name] then state[name]:stop(); state[name]=nil end
end

-- SIGTERM first, then SIGKILL after a grace period. A helper that ignored SIGTERM held
-- state.request forever (a timed-out request waits for the exit before launching a
-- replacement), so CI status stopped updating until a reload, and a reload orphaned it. The
-- escalation runs in a detached shell because Lua timers die with a reload, and it kills only
-- while the PID is still Hammerspoon's child, so a reused PID is never hit.
local KILL_GRACE = 3
local function terminateTask(task)
    local pid = task:isRunning() and task:pid() or nil
    task:terminate() -- Only our own helper, never a CI/test owner PID.
    if type(pid) ~= 'number' or pid <= 1 then return end
    os.execute(string.format(
        "(sleep %d; [ \"$(/bin/ps -o ppid= -p %d | /usr/bin/tr -d ' ')\" = %d ] && /bin/kill -KILL %d) </dev/null >/dev/null 2>&1 &",
        KILL_GRACE, pid, hs.processInfo.processID, pid))
end

function M.stop()
    state.running=false
    state.generation=state.generation+1
    state.pending=false
    for _,name in ipairs({'debounce', 'activeTimer', 'pathwatcher', 'wake'}) do stopResource(name) end
    local old=state.request
    if old then
        old.retired=true
        if old.deadline then old.deadline:stop(); old.deadline=nil end
        if not old.terminated then
            old.terminated=true
            terminateTask(old.task)
        end
        -- Retain its slot until the exit callback, even across an immediate start.
    end
end

local function summary(output)
    if type(output) ~= 'string' or #output > 4096 then return nil end
    local ok,value=pcall(hs.json.decode, output)
    if not ok or type(value) ~= 'table' then return nil end
    for key in pairs(value) do if key ~= 'activeCount' then return nil end end
    local count=value.activeCount
    if type(count) == 'number' and count >= 0 and count <= 512 and count % 1 == 0 then return count end
    return nil
end

local function complete(owned, code, output)
    if state.request ~= owned then return end
    state.request=nil
    if owned.deadline then owned.deadline:stop(); owned.deadline=nil end
    if state.running and owned.generation == state.generation and not owned.retired then
        if not enabled() then M.stop(); return end
        local count=not owned.timedOut and code == 0 and summary(output) or nil
        if count == 0 then
            stopResource('activeTimer')
        elseif count then
            if not state.activeTimer then
                local generation=state.generation
                state.activeTimer=hs.timer.doEvery(state.config.interval, function()
                    if state.running and generation == state.generation then request() end
                end)
            end
        else
            advisory() -- Retain a previously active timer; failure is not idle.
        end
    end
    if state.running and state.pending then
        state.pending=false
        stopResource('debounce')
        request()
    end
end

request = function()
    if not state.running then return end
    if not enabled() then M.stop(); return end
    if state.request then state.pending=true; return end
    stopResource('debounce')
    local owned={generation=state.generation}
    local task=hs.task.new(state.config.helperCommand, function(code, output)
        complete(owned, code, output)
    end, {'observe'})
    if not task then advisory(); return end
    owned.task=task
    state.request=owned
    if not task:start() then state.request=nil; advisory(); return end
    owned.deadline=hs.timer.doAfter(15, function()
        if state.request ~= owned then return end
        owned.deadline=nil
        owned.timedOut=true
        owned.terminated=true
        advisory()
        terminateTask(task)
        -- Do not launch a replacement until the owned task actually exits.
    end)
end

local function schedule()
    if not state.running then return end
    stopResource('debounce')
    local generation=state.generation
    state.debounce=hs.timer.doAfter(0.25, function()
        state.debounce=nil
        if state.running and generation == state.generation then request() end
    end)
end

local recoveryFlags={'mustScanSubDirs','userDropped','kernelDropped','rootChanged','eventIdsWrapped','mount','unmount'}
local function changed(paths, flags)
    for _,flagTable in ipairs(flags or {}) do
        for _,flag in ipairs(recoveryFlags) do
            if flagTable[flag] then schedule(); return end
        end
    end
    local prefix=state.config.sharedRoot .. '/'
    for _,path in ipairs(paths or {}) do
        if type(path) == 'string' and path:sub(1,#prefix) == prefix then
            local directory=path:sub(#prefix+1):match('^([^/]+)')
            if directory and directory:match('^weekenduo%-ci%-status%-%d+$') then schedule(); return end
        end
    end
end

function M.start()
    M.stop()
    if not enabled() then return false end
    local ok,config=pcall(hs.json.read, configPath)
    if not ok or type(config) ~= 'table' or type(config.helperCommand) ~= 'string'
        or config.helperCommand:sub(1,1) ~= '/' or type(config.sharedRoot) ~= 'string'
        or config.sharedRoot:sub(1,1) ~= '/' or type(config.interval) ~= 'number'
        or config.interval < 1 or config.interval > 60 or config.interval % 1 ~= 0 then
        advisory(); return false
    end
    config.sharedRoot=config.sharedRoot:gsub('/+$','')
    if config.sharedRoot == '' then advisory(); return false end
    state.config=config
    state.running=true
    local generation=state.generation
    local started=pcall(function()
        state.pathwatcher=hs.pathwatcher.new(config.sharedRoot, function(paths, flags)
            if state.running and generation == state.generation then changed(paths, flags) end
        end)
        assert(state.pathwatcher:start())
        state.wake=hs.caffeinate.watcher.new(function(event)
            if state.running and generation == state.generation and event == hs.caffeinate.watcher.systemDidWake then schedule() end
        end)
        assert(state.wake:start())
    end)
    if not started then M.stop(); advisory(); return false end
    request() -- One startup/reload scan; a successful idle response leaves no timer.
    return true
end

-- Match NanoWM's existing callback chaining; a reload must not orphan a helper.
local previousShutdown=hs.shutdownCallback
hs.shutdownCallback=function()
    M.stop()
    if previousShutdown then previousShutdown() end
end

return M
