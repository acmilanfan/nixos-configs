-- Execute with locked Lua, never inside the live Hammerspoon instance.
local ROOT = 'dotfiles/hammerspoon/nanowm/'
local function equal(a, b, why) assert(a == b, (why or '') .. ': expected ' .. tostring(b) .. ', got ' .. tostring(a)) end
local function setup(options)
    options = options or {}
    local f = {now=0, timers={}, tasks={}, watches={}, logs={}, enabled=options.enabled ~= false, live=0, maxLive=0}
    local function timer(delay, fn, repeating)
        local t = {due=f.now+delay, fn=fn, interval=repeating and delay, stopped=false}
        function t:stop() self.stopped=true; return self end
        table.insert(f.timers, t); return t
    end
    function f.advance(delta)
        local target=f.now+delta
        for _=1,1000 do
            local nextTimer
            for _,t in ipairs(f.timers) do
                if not t.stopped and t.due <= target and (not nextTimer or t.due < nextTimer.due) then nextTimer=t end
            end
            if not nextTimer then f.now=target; return end
            f.now=nextTimer.due
            if nextTimer.interval then nextTimer.due=f.now+nextTimer.interval else nextTimer.stopped=true end
            nextTimer.fn()
        end
        error('runaway timer loop')
    end
    function f.liveTimers()
        local n=0; for _,t in ipairs(f.timers) do if not t.stopped then n=n+1 end end; return n
    end
    local config = {helperCommand='/fixture/bin/local-ci-status', sharedRoot=options.sharedRoot or '/Users/Shared', interval=options.interval or 3}
    local function watch(fn)
        local w={fn=fn, stopped=false}; function w:start() return self end
        function w:stop() self.stopped=true; return self end; return w
    end
    hs = {
        fs={attributes=function() return f.enabled and 'file' or nil end},
        json={read=function() return options.badConfig and {} or config end,
            decode=function(s)
                local n=s:match('^%s*{%s*"activeCount"%s*:%s*([%d%.%-]+)%s*}%s*$')
                if n then return {activeCount=tonumber(n)} end
                if s == '{"activeCount":true}' then return {activeCount=true} end
                error('invalid JSON')
            end},
        printf=function(message) table.insert(f.logs,message) end,
        timer={doAfter=function(d,fn) return timer(d,fn,false) end, doEvery=function(d,fn) return timer(d,fn,true) end},
        pathwatcher={new=function(path,fn) local w=watch(fn); w.path=path; table.insert(f.watches,w); return w end},
        caffeinate={watcher={systemDidWake=1,new=function(fn) f.wake=watch(fn); return f.wake end}},
        task={new=function(executable,fn,args)
            equal(executable,'/fixture/bin/local-ci-status','trusted executable')
            equal(#args,1); equal(args[1],'observe','fixed argv, no paths/code')
            if options.newFail then return nil end
            local t={callback=fn, terminated=0, running=false}
            function t:start()
                if options.startFail then return nil end
                self.running=true; f.live=f.live+1; f.maxLive=math.max(f.maxLive,f.live); return self
            end
            function t:terminate() self.terminated=self.terminated+1; return self end
            function t:complete(output,code)
                if self.running then self.running=false; f.live=f.live-1 end
                self.callback(code or 0,output or '{"activeCount":0}','')
            end
            table.insert(f.tasks,t); return t
        end}
    }
    if options.previousShutdown then hs.shutdownCallback=function() f.previousShutdownCalls=(f.previousShutdownCalls or 0)+1 end end
    f.controller=dofile(ROOT .. 'ci_watch.lua')
    function f.event(paths, flags) f.watches[#f.watches].fn(paths,flags or {}) end
    return f
end
local tests={}

function tests.idle_start_active_tick_inflight_finish_then_idle()
    local f=setup(); assert(f.controller.start()); equal(#f.tasks,1)
    equal(f.watches[1].path,'/Users/Shared')
    f.tasks[1]:complete(); f.advance(120); equal(#f.tasks,1); equal(f.liveTimers(),0,'no idle timers')
    f.event({'/Users/Shared/unrelated/file'}); f.advance(1); equal(#f.tasks,1)
    f.event({'/Users/Shared/weekenduo-ci-status-501/manual-test.json'})
    f.advance(0.249); equal(#f.tasks,1); f.advance(0.001); equal(#f.tasks,2)
    f.tasks[2]:complete('{"activeCount":1}'); f.advance(3); equal(#f.tasks,3,'active timer ticks')
    f.event({'/Users/Shared/weekenduo-ci-status-501/manual-test.json'})
    f.advance(0.25); equal(#f.tasks,3,'single flight')
    f.tasks[3]:complete('{"activeCount":0}'); equal(#f.tasks,4,'pending finish rescan')
    f.tasks[4]:complete(); f.advance(120); equal(#f.tasks,4); equal(f.liveTimers(),0); equal(f.maxLive,1)
end

function tests.bursts_and_injection_paths_are_hints_only()
    local f=setup(); f.controller.start(); f.tasks[1]:complete()
    for _=1,20 do f.event({'/Users/Shared/weekenduo-ci-status-501/x;$(cmd).json'}) end
    f.advance(0.25); equal(#f.tasks,2); f.tasks[2]:complete()
    for _,p in ipairs({'/Users/Shared/weekenduo-ci-status-501evil/a','/Users/Shared/not-weekenduo-ci-status-501/a',
                        '/Users/Shared/weekenduo-ci-status-/a','/evil/Users/Shared/weekenduo-ci-status-501/a'}) do
        f.event({p})
    end
    f.advance(60); equal(#f.tasks,2)
end

function tests.invalid_results_never_stop_a_previously_active_timer()
    local f=setup(); f.controller.start(); f.tasks[1]:complete('{"activeCount":1}')
    for _,output in ipairs({'', '{}', '{"activeCount":true}', '{"activeCount":-1}', '{"activeCount":1.5}', '{"activeCount":513}'}) do
        f.advance(3); f.tasks[#f.tasks]:complete(output)
    end
    f.advance(3); f.tasks[#f.tasks]:complete('{"activeCount":0}',1)
    local before=#f.tasks; f.advance(3); equal(#f.tasks,before+1)
    f.tasks[#f.tasks]:complete(); f.advance(60); equal(#f.tasks,before+1); equal(f.liveTimers(),0)
end

function tests.idle_failure_or_unavailable_executable_has_no_retry_loop()
    for _,options in ipairs({{}, {newFail=true}, {startFail=true}}) do
        local f=setup(options); f.controller.start()
        if f.tasks[1] and f.tasks[1].running then f.tasks[1]:complete('',1) end
        local count=#f.tasks; f.advance(120); equal(#f.tasks,count); equal(f.liveTimers(),0)
    end
end

function tests.timeout_terminates_only_owned_helper_and_ignores_its_late_idle()
    local f=setup(); f.controller.start(); f.tasks[1]:complete('{"activeCount":1}')
    f.advance(3); local hung=f.tasks[2]; f.advance(15)
    equal(hung.terminated,1); equal(#f.tasks,2,'wait for owned task to exit')
    hung:complete('{"activeCount":0}'); equal(#f.tasks,3)
    f.tasks[3]:complete('{"activeCount":1}'); f.advance(3); equal(#f.tasks,4,'late idle ignored')
    f.tasks[4]:complete(); equal(f.maxLive,1)
end

function tests.restart_waits_for_old_task_exit_and_ignores_stale_callbacks()
    local f=setup(); f.controller.start(); local old=f.tasks[1]; local oldWatch=f.watches[1]
    f.controller.stop(); equal(old.terminated,1); assert(oldWatch.stopped); assert(f.wake.stopped)
    f.controller.start(); equal(#f.tasks,1,'no overlap during retirement')
    old:complete('{"activeCount":1}'); equal(#f.tasks,2)
    f.tasks[2]:complete(); old.callback(0,'{"activeCount":1}','')
    oldWatch.fn({'/Users/Shared/weekenduo-ci-status-501/file'},{})
    f.advance(60); equal(#f.tasks,2); equal(f.liveTimers(),0); equal(f.maxLive,1)
    f.controller.start(); equal(#f.tasks,3,'idempotent restart scan')
    assert(f.watches[2].stopped); f.tasks[3]:complete(); f.controller.stop()
end

function tests.wake_drop_flags_and_late_ci_directory_rescan()
    local f=setup(); f.controller.start(); f.tasks[1]:complete()
    f.wake.fn(hs.caffeinate.watcher.systemDidWake); f.advance(0.25); equal(#f.tasks,2); f.tasks[2]:complete()
    for _,flag in ipairs({'mustScanSubDirs','userDropped','kernelDropped','rootChanged','eventIdsWrapped','mount','unmount'}) do
        f.event({'/Users/Shared'},{{[flag]=true}}); f.advance(0.25)
        f.tasks[#f.tasks]:complete()
    end
    local n=#f.tasks
    f.event({'/Users/Shared/weekenduo-ci-status-9999'}); f.advance(0.25); equal(#f.tasks,n+1)
    f.tasks[#f.tasks]:complete(); f.advance(60); equal(f.liveTimers(),0)
end

function tests.disabled_and_invalid_config_initialize_nothing()
    for _,opts in ipairs({{enabled=false},{badConfig=true},{interval=0}}) do
        local f=setup(opts); assert(not f.controller.start()); equal(#f.tasks,0); equal(#f.watches,0); equal(f.liveTimers(),0)
    end
    local f=setup({interval=5}); f.controller.start(); f.tasks[1]:complete('{"activeCount":1}')
    f.advance(3); equal(#f.tasks,1); f.advance(2); equal(#f.tasks,2); f.tasks[2]:complete()
    f.controller.start(); f.tasks[3]:complete('{"activeCount":1}'); f.enabled=false
    f.advance(5); equal(#f.tasks,3); equal(f.liveTimers(),0); assert(f.watches[#f.watches].stopped)
end

function tests.hammerspoon_shutdown_stops_owned_resources_and_preserves_existing_callback()
    local f=setup({previousShutdown=true}); f.controller.start()
    hs.shutdownCallback()
    equal(f.previousShutdownCalls,1)
    equal(f.tasks[1].terminated,1)
    assert(f.watches[1].stopped); assert(f.wake.stopped); equal(f.liveTimers(),0)
end

function tests.nanowm_initialization_starts_the_real_controller()
    local f=setup()
    for _,name in ipairs({'profiler','config','state','core','layout','actions','tags','menus','overview','integrations','keybinds','watchers','agents'}) do
        local stub=setmetatable({enabled=false,caffeinateActive=false,VERSION='fixture'}, {__index=function() return function() end end})
        package.loaded['nanowm.' .. name]=stub
    end
    package.loaded['nanowm.ci_watch']=f.controller
    hs.host={uuid=function() return 'fixture' end}; hs.settings={set=function() end}
    hs.urlevent={bind=function() end}; hs.window={}; hs.alert={show=function() end}
    dofile(ROOT .. 'init.lua').init()
    equal(#f.tasks,1,'NanoWM init must start observer'); equal(#f.watches,1)
    f.tasks[1]:complete(); f.controller.stop()
end

local count=0
for name,test in pairs(tests) do
    local ok,err=pcall(test)
    if not ok then error(name .. ': ' .. tostring(err)) end
    count=count+1
end
print('watcher tests passed: ' .. count)

-- Optional ABI integration: summaries captured from the actual Python CLI,
-- while task execution, time and filesystem delivery remain safe fake boundaries.
local fixturePath=os.getenv('LOCAL_CI_OBSERVE_FIXTURE')
if fixturePath then
    local summaries={}; for line in io.lines(fixturePath) do table.insert(summaries,line) end
    equal(#summaries,4)
    local root=assert(os.getenv('LOCAL_CI_WATCH_ROOT'))
    local f=setup({sharedRoot=root}); f.controller.start(); f.tasks[1]:complete(summaries[1])
    f.advance(60); equal(#f.tasks,1,'actual idle summary stops all work')
    f.event({root .. '/weekenduo-ci-status-501/status.json'}); f.advance(0.25)
    f.tasks[2]:complete(summaries[2]); f.advance(3); equal(#f.tasks,3,'actual active summary starts timer')
    f.event({root .. '/weekenduo-ci-status-501/status.json'}); f.advance(0.25)
    f.tasks[3]:complete(summaries[3]); equal(#f.tasks,4,'finish while busy retains one rescan')
    f.tasks[4]:complete(summaries[4]); f.advance(60); equal(#f.tasks,4)
    equal(f.liveTimers(),0); equal(f.maxLive,1)
    print('actual Python summary to watcher lifecycle passed')
end
