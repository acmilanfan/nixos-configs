-- Pure fixtures in Hammerspoon's Lua runtime; never replaces global hs or calls GUI APIs.
local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)/tests/[^/]+$")
local decode = hs.json.decode
local function runTests()
    local core = assert(loadfile(root .. "/youtube-capture-core.lua", "t", setmetatable({ hs = false }, {__index = _G})))()
    local function fixture(options)
        options = options or {}
        local tabs = {
            { name = "first", url = "https://youtu.be/3V_wgHB4eFw" },
            { name = "original", url = "https://www.youtube.com/watch?v=abcdefghijk" },
            { name = "last", url = "https://example.org/" },
        }
        local state = { tabs = tabs, selected = tabs[2], focused = true, time = 0, queue = {}, events = {}, notices = {}, runs = 0 }
        local adapter = {}
        function adapter.snapshot() return { window = state, tabs = tabs, selected = tabs[2], verifyTab = options.cold and tabs[1] or nil, complete = not options.incomplete, reason = "unsupported collapsed group" } end
        function adapter.isFocused() return state.focused end
        function adapter.isValid(element) return not element.closed end
        function adapter.select(tab)
            if tab.closed then return false, "tab closed" end
            state.selected = tab
            state.events[#state.events + 1] = tab == tabs[2] and "restore:original" or "select:" .. tab.name
            return true
        end
        function adapter.selected() return state.selected end
        function adapter.readURL(_, tab)
            if options.readError then return nil, "address bar is being edited" end
            if options.pending and tab == tabs[1] then
                state.reads = (state.reads or 0) + 1
                if state.reads <= options.pending then return nil, "pending" end
            end
            return tab.url
        end
        function adapter.schedule(seconds, fn)
            local timer = { at = state.time + seconds, fn = fn }
            function timer:stop() self.stopped = true end
            state.queue[#state.queue + 1] = timer
            return timer
        end
        function adapter.now() return state.time end
        function adapter.notify(text) state.notices[#state.notices + 1] = text end
        function adapter.run(urls, callback)
            state.runs = state.runs + 1
            state.urls = urls
            state.events[#state.events + 1] = "run:" .. #urls
            callback(options.exit or 0, options.output or '{"saved":2,"existing":0,"failed":0,"items":[]}', options.stderr or "")
        end
        function adapter.traversalChanged(active) state.traversing = active end
        state.controller = core.new(adapter, { decode = options.decode or decode })
        function state.step()
            table.sort(state.queue, function(a,b) return a.at < b.at end)
            local timer = table.remove(state.queue, 1)
            if timer then state.time = timer.at; if not timer.stopped then timer.fn() end end
            return timer ~= nil
        end
        function state.drain()
            for _ = 1, 5000 do if not state.step() then return end end
            error("unbounded timer loop")
        end
        return state
    end

    local tests = {}
    function tests.current_does_not_select()
        local s = fixture(); s.controller.start("current"); s.drain()
        assert(s.runs == 1 and #s.urls == 1 and s.urls[1]:find("abcdefghijk", 1, true))
        assert(#s.events == 1 and not s.controller.busy())
    end
    function tests.cold_current_verifies_by_roundtrip_but_saves_only_original()
        local s=fixture({cold=true});s.controller.start("current");s.drain()
        assert(s.events[1]=="select:first" and s.runs==1 and #s.urls==1)
        assert(s.urls[1]:find("abcdefghijk",1,true) and s.selected==s.tabs[2])
    end
    function tests.window_restores_before_run()
        local s = fixture(); s.controller.start("window"); s.drain()
        assert(s.events[#s.events - 1] == "restore:original" and s.events[#s.events] == "run:2")
        assert(s.selected == s.tabs[2] and s.runs == 1 and not s.traversing)
        assert(table.concat(s.notices, " "):find("skipped: 1", 1, true))
    end
    function tests.duplicate_titles_do_not_end_scan()
        local s = fixture(); s.tabs[3].name = s.tabs[1].name; s.tabs[3].url = s.tabs[1].url
        s.controller.start("window"); s.drain()
        assert(s.runs == 1 and #s.urls == 3, "URL dedup belongs to Go, not traversal termination")
    end
    function tests.stale_url_waits_for_selected_tab()
        local s = fixture({ pending = 2 }); s.controller.start("window"); s.drain()
        assert(s.reads >= 3 and s.runs == 1 and s.urls[1]:find("3V_wgHB4eFw", 1, true))
    end
    function tests.focus_loss_does_not_restore_or_dispatch()
        local s = fixture(); s.controller.start("window"); s.focused = false; s.drain()
        assert(s.runs == 0 and not s.controller.busy())
        assert(s.events[#s.events] ~= "restore:original")
    end
    function tests.cancel_dispatches_nothing()
        local s = fixture(); s.controller.start("window"); s.controller.cancel("user cancelled"); s.drain()
        assert(s.runs == 0 and s.selected == s.tabs[2] and not s.controller.busy())
    end
    function tests.unsupported_groups_report_incomplete()
        local s = fixture({ incomplete = true }); s.controller.start("window"); s.drain()
        assert(s.runs == 0 and table.concat(s.notices, " "):find("group", 1, true))
        s.controller.start("current"); s.drain(); assert(s.runs == 1)
    end
    function tests.edited_address_bar_aborts()
        local s = fixture({ readError = true }); s.controller.start("window"); s.drain()
        assert(s.runs == 0 and s.selected == s.tabs[2])
    end
    function tests.closed_tab_aborts_without_partial_save()
        local s = fixture(); s.controller.start("window"); s.tabs[3].closed = true; s.drain()
        assert(s.runs == 0 and not s.controller.busy())
    end
    function tests.already_visited_tab_closed_before_commit_aborts()
        local s=fixture();s.controller.start("window");s.step()
        s.tabs[1].closed=true;s.drain()
        assert(s.runs==0,"closed previously visited tab still dispatched")
    end
    function tests.closed_window_aborts_without_restore()
        local s = fixture(); s.controller.start("window"); s.closed = true; s.drain()
        assert(s.runs == 0 and s.events[#s.events] ~= "restore:original")
    end
    function tests.overlap_and_deadlines()
        local s = fixture({ pending = 10000 }); s.controller.start("window"); s.controller.start("window"); s.drain()
        assert(s.runs == 0 and s.time < 10 and not s.controller.busy())
    end
    function tests.too_many_tabs_fails_before_traversal()
        local s = fixture()
        for i = 4, 4097 do s.tabs[i] = {name="extra",url="https://example.org"} end
        s.controller.start("window");s.drain()
        assert(s.runs == 0 and #s.events == 0 and not s.controller.busy())
    end
    function tests.malformed_and_partial_result_feedback()
        for _, options in ipairs({ { output = "not-json" }, { exit = 1, output = '{"saved":1,"existing":0,"failed":1,"items":[{"id":"abcdefghijk","status":"failed"}]}' } }) do
            local s = fixture(options); s.controller.start("current"); s.drain()
            local notice = table.concat(s.notices, " ")
            assert(notice:find("fail") or notice:find("Invalid"), notice)
        end
    end
    function tests.non_json_response_does_not_reach_native_decoder()
        local calls = 0
        local s = fixture({output="not-json", decode=function() calls=calls+1;return nil end})
        s.controller.start("current");s.drain()
        assert(calls == 0, "plain stderr/stdout sent to noisy native JSON decoder")
    end
    function tests.missing_helper_feedback_is_actionable()
        local s = fixture({exit=1,output="",stderr="helper missing; install youtube-org first"})
        s.controller.start("current");s.drain()
        assert(table.concat(s.notices," "):find("install youtube-org",1,true))
    end

    -- Exercise the real AX adapter against structurally complete browser-chrome fixtures.
    local function node(role, id, children, extra)
        local attrs = { AXRole = role, AXDOMIdentifier = id, AXChildren = children or {} }
        for k,v in pairs(extra or {}) do attrs[k] = v end
        local n = { attrs = attrs }
        function n:attributeValue(k) return self.attrs[k] end
        function n:isValid() return not self.closed end
        function n:performAction(action) assert(action == "AXPress"); return self end
        return n
    end
    local function liveFixture(nixHelper)
        local tab1 = node("AXRadioButton", "", nil, { AXSelected = true })
        local tab2 = node("AXRadioButton", "", nil, { AXSelected = false })
        local sidebar = node("AXRadioButton", "main-button", nil, { AXSelected = true })
        local strip = node("AXTabGroup", "tabbrowser-tabs", {tab1,tab2})
        local address = node("AXComboBox", "urlbar-input", nil, { AXValue = "www.youtube.com/watch?v=3V_wgHB4eFw" })
        local page = node("AXWebArea", "", {node("AXRadioButton", "page-content")}, { AXURL = {url = "https://www.youtube.com/watch?v=3V_wgHB4eFw"} })
        local rootNode = node("AXWindow", "", {node("AXToolbar", "", {address}),strip,sidebar,page})
        local app = {}; function app:bundleID() return "org.mozilla.firefox" end; function app:pid() return 12 end
        local win = {}; function win:id() return 45 end; function win:application() return app end
        local fake = {
            application = { frontmostApplication = function() return app end },
            window = { focusedWindow = function() return win end },
            axuielement = { windowElement = function() return rootNode end },
            timer = { secondsSinceEpoch = function() return 0 end },
            alert = { show = function() end },
            pasteboard = setmetatable({}, {__index = function() error("clipboard access forbidden") end}),
        }
        local env = setmetatable({ hs = fake, _G = {}, require = function(name)
            if name == "youtube-capture-config" and nixHelper then return {helper=nixHelper} end
            assert(name == "youtube-capture-core"); return core
        end }, {__index = _G})
        local module = assert(loadfile(root .. "/youtube-capture.lua", "t", env))()
        return module.newAdapter({ hs = fake }), page, tab1, tab2, address, strip, module, fake, rootNode
    end
    function tests.adapter_reads_url_without_sidebar_or_page_controls()
        local a, _, tab1, _, address, strip = liveFixture()
        strip.attrs.AXChildren={tab1} -- one exposed tab has no competing live page
        local snapshot = assert(a.snapshot()); assert(#snapshot.tabs == 1 and snapshot.selected == tab1)
        assert(a.readURL(snapshot.window,tab1) == "https://www.youtube.com/watch?v=3V_wgHB4eFw")
        address.attrs.AXFocused = true
        local url, err = a.readURL(snapshot.window,tab1); assert(not url and err ~= "pending")
    end
    function tests.initial_unassociated_page_is_not_accepted()
        local a, _, tab1, tab2 = liveFixture()
        tab1.attrs.AXSelected=false;tab2.attrs.AXSelected=true
        local snapshot=a.snapshot()
        assert(a.readURL(snapshot.window,tab2)==nil, "accepted A's coherent URL while B is selected")
    end
    function tests.initial_stale_page_cannot_dispatch_through_real_core()
        local a, _, tab1, tab2, _, _, _, fake = liveFixture()
        tab1.attrs.AXSelected=false;tab2.attrs.AXSelected=true
        local now,queue,runs=0,{},0
        fake.timer.secondsSinceEpoch=function()return now end
        fake.timer.doAfter=function(seconds,fn)
            local timer={at=now+seconds,fn=fn};function timer:stop()self.stopped=true end
            queue[#queue+1]=timer;return timer
        end
        a.run=function(_,callback) runs=runs+1;callback(0,'{"saved":1,"existing":0,"failed":0,"items":[]}',"") end
        local c=core.new(a,{decode=decode});c.start("current")
        for _=1,300 do
            local timer=table.remove(queue,1);if not timer then break end
            now=timer.at;if not timer.stopped then timer.fn() end
        end
        assert(runs==0, "initial stale page dispatched through real core/adapter")
    end
    function tests.adapter_rejects_stale_page_after_selection()
        local a, page, tab1, tab2, address = liveFixture()
        local snapshot = a.snapshot(); assert(a.select(tab2));tab1.attrs.AXSelected=false;tab2.attrs.AXSelected=true
        assert(a.readURL(snapshot.window,tab2) == nil, "old page was attributed to selected tab")
        -- Mismatched address/page URL is never accepted, even if element identity updates.
        address.attrs.AXValue = "youtube.com/watch?v=abcdefghijk"
        assert(a.readURL(snapshot.window,tab2) == nil)
    end
    function tests.adapter_reports_collapsed_groups()
        local a, _, _, _, _, strip = liveFixture()
        strip.attrs.AXChildren[#strip.attrs.AXChildren + 1] = node("AXDisclosureTriangle", "", {}, {AXExpanded=false})
        assert(a.snapshot().complete == false)
    end
    function tests.required_tab_children_error_cannot_claim_complete()
        local a, _, tab1, tab2, _, strip=liveFixture()
        local group=node("AXGroup","",{tab2})
        function group:attributeValue(key)
            if key=="AXChildren" then return nil,"AXErrorCannotComplete" end
            return self.attrs[key]
        end
        strip.attrs.AXChildren={tab1,group}
        local snapshot=a.snapshot()
        assert(not snapshot or snapshot.complete==false, "unreadable tab subtree reported complete")
    end
    function tests.native_unsupported_optional_attrs_and_empty_leaf_are_valid()
        local a, _, _, _, _, _, _, _, window=liveFixture()
        function window:attributeValue(key)
            if key=="AXDOMIdentifier" then return nil,"Attribute is not supported by target" end
            return self.attrs[key]
        end
        local leaf=node("AXButton",nil)
        leaf.attrs.AXChildren=nil
        function leaf:attributeValue(key)
            if key=="AXDOMIdentifier" then return nil,"Attribute is not supported by target" end
            return self.attrs[key]
        end
        window.attrs.AXChildren[#window.attrs.AXChildren+1]=leaf
        local snapshot,err=a.snapshot()
        assert(snapshot and snapshot.complete and #snapshot.tabs==2,err)
    end
    function tests.subsequent_tab_enumeration_errors_do_not_return_partial_selection()
        local a, _, tab1, tab2, _, strip=liveFixture()
        local snapshot=a.snapshot()
        local group=node("AXGroup","",{tab2})
        function group:attributeValue(key)
            if key=="AXChildren" then return nil,"AXErrorCannotComplete" end
            return self.attrs[key]
        end
        strip.attrs.AXChildren={tab1,group}
        assert(a.selected(snapshot.window)==nil)
    end
    function tests.subsequent_hidden_group_does_not_return_complete_selection()
        local a, _, _, _, _, strip=liveFixture();local snapshot=a.snapshot()
        strip.attrs.AXChildren[#strip.attrs.AXChildren+1]=node("AXDisclosureTriangle","",{},{AXExpanded=false})
        assert(a.selected(snapshot.window)==nil,"incomplete later enumeration accepted")
    end
    function tests.adapter_accepts_new_page_only_after_coherent_url_update()
        local a, _, tab1, tab2, address, _, _, _, window = liveFixture()
        local snapshot = a.snapshot();a.select(tab2)
        tab1.attrs.AXSelected=false;tab2.attrs.AXSelected=true
        window.attrs.AXChildren[4] = node("AXWebArea", "", {}, {AXURL={url="https://www.youtube.com/watch?v=abcdefghijk"}})
        assert(a.readURL(snapshot.window,tab2) == nil, "stale address bar accepted")
        address.attrs.AXValue = "www.youtube.com/watch?v=abcdefghijk"
        assert(a.readURL(snapshot.window,tab2) == "https://www.youtube.com/watch?v=abcdefghijk")
    end
    function tests.adapter_search_is_bounded()
        local a, _, _, _, _, _, _, _, window = liveFixture()
        for _ = 1, 600 do window.attrs.AXChildren[#window.attrs.AXChildren+1] = node("AXButton", "") end
        local snapshot, err = a.snapshot()
        assert(not snapshot and err:find("limit",1,true))
    end
    function tests.hidden_webarea_descendants_are_never_chrome()
        local a, _, tab1, _, _, _, _, _, window=liveFixture()
        local rogue=node("AXRadioButton","",{}, {AXSelected=true})
        local hidden=node("AXWebArea","",{
            node("AXTabGroup","tabbrowser-tabs",{rogue}),
            node("AXComboBox","urlbar-input",{}, {AXValue="attacker content"}),
        },{AXHidden=true})
        local reads=0
        function hidden:attributeValue(key)
            if key=="AXChildren" then reads=reads+1 end
            return self.attrs[key]
        end
        window.attrs.AXChildren[#window.attrs.AXChildren+1]=hidden
        local snapshot=a.snapshot()
        assert(reads==0 and snapshot and #snapshot.tabs==2 and snapshot.selected==tab1, "hidden webpage crossed chrome boundary")
    end
    function tests.adapter_missing_helper_is_a_failure()
        local a, _, _, _, _, _, _, fake = liveFixture()
        fake.fs = { attributes = function() return nil end }
        local code
        a.run({"https://youtu.be/3V_wgHB4eFw"}, function(c) code=c end)
        assert(code ~= nil and code ~= 0)
    end
    function tests.adapter_uses_generated_nix_helper()
        local expected="/nix/store/fixture-youtube-org/bin/youtube-org"
        local a, _, _, _, _, _, _, fake=liveFixture(expected)
        local invoked,input
        fake.fs={attributes=function(path)assert(path==expected,"manual helper path still used");return {mode="file"}end}
        fake.task={new=function(path,callback,args)
            invoked=path;assert(table.concat(args," ")=="save --json --stdin")
            return {setInput=function(_,data)input=data end,start=function()callback(0,'{"saved":1,"existing":0,"failed":0,"items":[]}',"");return true end}
        end}
        a.run({"https://youtu.be/3V_wgHB4eFw"},function(code)assert(code==0)end)
        assert(invoked==expected and input=="https://youtu.be/3V_wgHB4eFw\n")
    end
    function tests.setup_observes_middle_click_and_scroll_interruption()
        for _,interruption in ipairs({4,5}) do
            local _, _, _, _, _, _, module, fake=liveFixture()
            local subscribed, callback
            local function object()
                return {start=function(self)return self end,stop=function()end,enable=function()end,disable=function()end,delete=function()end}
            end
            fake.application.watcher={activated=1,terminated=2,new=function()return object()end}
            fake.hotkey={new=function()return object()end}
            fake.keycodes={map={escape=53}}
            fake.json={decode=decode}
            fake.timer.doAfter=function()return object()end
            fake.eventtap={event={types={keyDown=1,leftMouseDown=2,rightMouseDown=3,otherMouseDown=4,scrollWheel=5}},new=function(types,fn)subscribed=types;callback=fn;return object()end}
            fake.task={new=function()error("cancelled traversal dispatched a helper")end}
            local handle=module.setup({hs=fake})
            handle.controller.start("window")
            local observed=false;for _,value in ipairs(subscribed or {}) do if value==interruption then observed=true end end
            assert(observed,"physical interruption not subscribed: "..interruption)
            local event={getType=function()return interruption end,getKeyCode=function()return 0 end}
            callback(event)
            assert(not handle.controller.busy(),"interrupted traversal still active")
            handle.stop()
        end
    end

    local count, failures = 0, {}
    for name, test in pairs(tests) do
        local ok, err = xpcall(test, debug.traceback)
        if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
        count = count + 1
    end
    assert(#failures == 0, table.concat(failures, "\n"))
    print("PASS: youtube capture fixture tests (" .. count .. " cases)")
end
local ok, err = xpcall(runTests, debug.traceback)
if not ok then print("FAIL: youtube capture fixture tests\n" .. tostring(err)) end
