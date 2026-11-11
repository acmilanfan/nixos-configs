-- Explicit Firefox captures only. No clipboard, profile scraping, JS, or server.
local core = require("youtube-capture-core")
local M = {}
local FIREFOX = "org.mozilla.firefox"

local function attr(element, name)
    if not element then return nil end
    local ok, value = pcall(element.attributeValue, element, name)
    if ok then return value end
end

-- Browser chrome + WebArea roots only: never descend into page content.
local function chrome(root)
    local found = {}
    local queue, seen = { {root, 0} }, {}
    local i = 1
    while queue[i] do
        if i > 512 then return nil, "browser accessibility tree exceeds safe search limit" end
        local element, depth = queue[i][1], queue[i][2]
        i = i + 1
        if not seen[element] then
            seen[element] = true
            local role, id = attr(element, "AXRole"), attr(element, "AXDOMIdentifier")
            if id == "urlbar-input" then found.address = element end
            if id == "tabbrowser-tabs" then found.strip = element end
            if role == "AXWebArea" and attr(element, "AXHidden") ~= true then
                if found.page then return nil, "ambiguous current browser page" end
                found.page = element
            elseif id ~= "tabbrowser-tabs" and depth < 8 then
                for _, child in ipairs(attr(element, "AXChildren") or {}) do queue[#queue + 1] = {child, depth + 1} end
            end
        end
    end
    return found
end

local function browserTabs(strip)
    local tabs, complete, reason = {}, true, nil
    local queue, seen, i = { {strip,0} }, {}, 1
    while queue[i] do
        if i > 8192 then return nil, false, "tab tree exceeds safe search limit" end
        local element, depth = queue[i][1], queue[i][2]
        i = i + 1
        if not seen[element] then
            seen[element] = true
            local role = attr(element, "AXRole")
            local id = attr(element, "AXDOMIdentifier") or ""
            if attr(element, "AXHidden") == true or attr(element, "AXExpanded") == false
                or role == "AXDisclosureTriangle" or id:find("tab-group", 1, true) then
                complete, reason = false, "grouped/hidden tabs are not safely enumerable; expand or ungroup them first"
            end
            if role == "AXRadioButton" then tabs[#tabs + 1] = element end
            local children = attr(element, "AXChildren") or {}
            if depth >= 12 and #children > 0 then complete, reason = false, "tab tree depth exceeds safe search limit"
            elseif role ~= "AXRadioButton" then
                for _, child in ipairs(children) do queue[#queue + 1] = {child, depth + 1} end
            end
        end
    end
    for _, tab in ipairs(tabs) do
        local count = attr(tab, "AXARIASetSize")
        if type(count) == "number" and count > #tabs then complete, reason = false, "Firefox reports tabs missing from accessibility enumeration" end
    end
    return tabs, complete, reason
end

local function selected(tabs)
    local current
    for _, tab in ipairs(tabs) do
        if attr(tab, "AXSelected") == true or attr(tab, "AXValue") == true then
            if current then return nil end
            current = tab
        end
    end
    return current
end

local function locationText(value)
    if type(value) ~= "string" then return nil end
    return value:gsub("^https?://", ""):gsub("^www%.", ""):gsub("/$", "")
end

function M.newAdapter(options)
    options = options or {}
    local h = options.hs or hs
    local helper = options.helper or (os.getenv("HOME") .. "/.local/bin/youtube-org")
    local adapter, selection = {}, nil
    local liveTask, alert
    function adapter.notify(text)
        if alert and h.alert.closeSpecific then h.alert.closeSpecific(alert) end
        alert = h.alert.show("YouTube: " .. text, 5)
    end
    function adapter.now()
        if h.timer.absoluteTime then return h.timer.absoluteTime() / 1000000000 end
        return h.timer.secondsSinceEpoch()
    end
    function adapter.schedule(seconds, fn) return h.timer.doAfter(seconds, fn) end
    function adapter.isValid(element)
        element = type(element) == "table" and element.root or element
        if not element then return false end
        local ok, valid = pcall(element.isValid, element)
        return ok and valid == true
    end
    function adapter.isFocused(window)
        local app, win = h.application.frontmostApplication(), h.window.focusedWindow()
        return app and win and app:bundleID() == FIREFOX and app:pid() == window.pid and win:id() == window.win:id()
    end
    function adapter.snapshot()
        selection = nil
        local app, win = h.application.frontmostApplication(), h.window.focusedWindow()
        if not app or app:bundleID() ~= FIREFOX or not win then return nil, "focus a Firefox window first" end
        local root = h.axuielement.windowElement(win)
        if not root then return nil, "Firefox window is not accessible" end
        local parts, err = chrome(root)
        if not parts or not parts.strip or not parts.address then return nil, err or "Firefox browser controls unavailable" end
        local tabs, complete, reason = browserTabs(parts.strip)
        if not tabs then return nil, reason end
        local current = selected(tabs)
        if not current then return nil, "cannot identify one selected browser tab" end
        return { window = {root=root,win=win,pid=app:pid(),strip=parts.strip}, tabs=tabs, selected=current, complete=complete, reason=reason }
    end
    function adapter.selected(window)
        local tabs = browserTabs(window.strip)
        return tabs and selected(tabs)
    end
    function adapter.select(tab)
        local win = h.window.focusedWindow()
        local root = win and h.axuielement.windowElement(win)
        local parts = root and chrome(root)
        if not parts then return false end
        local tabs = parts.strip and browserTabs(parts.strip)
        selection = {tab=tab,oldPage=parts.page,changed=not tabs or selected(tabs) ~= tab}
        local ok, result = pcall(tab.performAction, tab, "AXPress")
        return ok and result ~= nil and result ~= false
    end
    function adapter.readURL(window, tab)
        if not adapter.isFocused(window) or adapter.selected(window) ~= tab then return nil, "pending" end
        local parts, err = chrome(window.root)
        if not parts or not parts.address then return nil, err or "address bar inaccessible" end
        if attr(parts.address, "AXFocused") == true then return nil, "address bar is being edited" end
        if selection and selection.tab == tab and selection.changed and (not parts.page or parts.page == selection.oldPage) then return nil, "pending" end
        local url = attr(parts.page, "AXURL")
        if type(url) == "table" then url = url.url end
        if type(url) ~= "string" or url == "" then return nil, "pending" end
        local display = attr(parts.address, "AXValue")
        if url:match("^https?://") and locationText(display) ~= locationText(url) then return nil, "pending" end
        if adapter.selected(window) ~= tab then return nil, "pending" end
        return url
    end
    function adapter.run(urls, callback)
        local info = h.fs.attributes(helper)
        if not info or info.mode ~= "file" then callback(1, "", "helper missing; install youtube-org first"); return end
        local task
        task = h.task.new(helper, function(code, out, err)
            if liveTask == task then liveTask = nil end
            callback(code, out, err)
        end, {"save","--json","--stdin"})
        if not task then callback(1, "", "helper could not start"); return end
        if options.orgRoot or options.credentialsDir then
            local env = {}
            for k,v in pairs(h.processInfo.environment) do env[k]=v end
            if options.orgRoot then env.YOUTUBE_ORG_ROOT = options.orgRoot end
            if options.credentialsDir then env.YOUTUBE_ORG_CREDENTIALS_DIR = options.credentialsDir end
            task:setEnvironment(env)
        end
        task:setInput(table.concat(urls,"\n") .. "\n")
        liveTask = task
        if not task:start() then liveTask = nil; callback(1, "", "helper could not start") end
    end
    return adapter
end

function M.setup(options)
    options = options or {}
    local h = options.hs or hs
    if _G.youtubeCapture then _G.youtubeCapture.stop() end
    local adapter = M.newAdapter(options)
    local controller = core.new(adapter, {decode=h.json.decode})
    local tap
    adapter.traversalChanged = function(active)
        if tap then tap:stop(); tap=nil end
        if not active then return end
        local types = h.eventtap.event.types
        tap = h.eventtap.new({types.keyDown,types.leftMouseDown,types.rightMouseDown}, function(event)
            local escape = event:getType() == types.keyDown and event:getKeyCode() == h.keycodes.map.escape
            controller.cancel(escape and "Capture cancelled" or "Capture interrupted by user")
            return escape
        end):start()
    end
    local current = h.hotkey.new({"cmd","alt"},"y",function() controller.start("current") end)
    local window = h.hotkey.new({"cmd","alt","shift"},"y",function() controller.start("window") end)
    local function sync()
        local app = h.application.frontmostApplication()
        if app and app:bundleID() == FIREFOX then current:enable();window:enable()
        else current:disable();window:disable();controller.cancel("Capture cancelled: Firefox lost focus") end
    end
    local watcher = h.application.watcher.new(function(_,event)
        if event == h.application.watcher.activated or event == h.application.watcher.terminated then sync() end
    end):start()
    local handle = {controller=controller}
    function handle.stop()
        controller.cancel("Capture configuration stopped")
        if tap then tap:stop() end
        watcher:stop();current:delete();window:delete()
    end
    _G.youtubeCapture = handle
    sync()
    return handle
end

return M
