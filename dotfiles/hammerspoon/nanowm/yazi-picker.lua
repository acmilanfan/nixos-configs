-- Native Open/Upload dialog bridge. Ctrl+Alt+Y starts a separate chooser;
-- Alt+Y remains the ordinary file manager. Never confirms the final Open button.
local core = require("nanowm.core")
local state = require("nanowm.state")
local M = {}
local active
local pickerWindow

-- Yazi overwrites its title, so Alt+Y must exclude the chooser by identity.
-- Retain the last window until it closes, including the brief post-handoff gap.
function M.isPickerWindow(win)
    return (pickerWindow ~= nil and pickerWindow:id() == win:id())
        or (active ~= nil and active.phase == "capturing" and win:title() == active.title)
end

local function attr(element, name)
    return element and element:attributeValue(name)
end

-- Stay at the window/sheet boundary: do not walk a browser's whole AX tree.
local function openPanel(root)
    if attr(root, "AXIdentifier") == "open-panel" then return root end
    for _, name in ipairs({ "AXSheets", "AXChildren" }) do
        for _, child in ipairs(attr(root, name) or {}) do
            if attr(child, "AXIdentifier") == "open-panel" then return child end
        end
    end
end

local function read(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local text = file:read(131072)
    file:close()
    return text or ""
end

local function clean(dir)
    if not dir then return end
    os.remove(dir .. "/selection")
    os.remove(dir .. "/done")
    os.remove(dir .. "/done.tmp")
    os.remove(dir .. "/ready")
    hs.fs.rmdir(dir)
end

local function finish(s, message)
    if active ~= s then return end
    if s.timer then s.timer:stop() end
    active = nil
    clean(s.dir)
    if message then hs.alert.show("Yazi picker: " .. message, 3) end
end

local function valid(s)
    return s.panel:isValid() and openPanel(s.root) == s.panel
end

local function focusOriginal(s)
    -- Tell NanoWM this focus change is intentional, including across tags.
    state.launchIntent = { app = s.app:name(), t = hs.timer.secondsSinceEpoch() }
    s.win:focus()
end

local function frontmost(s)
    local app = hs.application.frontmostApplication()
    return app and app:pid() == s.app:pid()
end

local function pathField(s)
    if not frontmost(s) then return nil end
    local field = attr(hs.axuielement.systemWideElement(), "AXFocusedUIElement")
    if attr(field, "AXRole") ~= "AXTextField" or attr(field, "AXIdentifier") ~= "PathTextField" then return nil end
    local parent = attr(field, "AXParent")
    if attr(parent, "AXIdentifier") ~= "GoToWindow" then return nil end
    for _ = 1, 6 do
        parent = attr(parent, "AXParent")
        if parent == s.panel then return field end
        if not parent then return nil end
    end
end

local function poll(s)
    if active ~= s then return end
    if hs.timer.secondsSinceEpoch() > s.deadline then
        finish(s, "timed out; the dialog was not submitted")
        return
    end
    if s.phase == "creating" then return end
    if not valid(s) then
        finish(s, "the original Open dialog has closed")
        return
    end

    if s.phase == "capturing" then
        local ghostty = hs.application.get("Ghostty")
        for _, win in ipairs(ghostty and ghostty:allWindows() or {}) do
            if win:title() == s.title then
                pickerWindow = win
                s.pickerAX = hs.axuielement.windowElement(win)
                core.floatCentered(win, 0.8)
                local ready = io.open(s.dir .. "/ready", "w")
                if not ready then finish(s, "could not start the chooser"); return end
                ready:close()
                s.phase = "choosing"
                s.deadline = hs.timer.secondsSinceEpoch() + 1800
                return
            end
        end
        return
    end

    if s.phase == "choosing" then
        local status = read(s.dir .. "/done")
        if not status then return end
        if not status:match("^0%s*$") then finish(s, "Yazi failed; no file was selected"); return end
        local selection = read(s.dir .. "/selection")
        if not selection or selection == "" then
            s.phase = "closing"
            s.deadline = hs.timer.secondsSinceEpoch() + 5
            return
        end
        local path = selection:gsub("\n$", "")
        local info = hs.fs.attributes(path)
        if path:sub(1, 1) ~= "/" or path:find("[%c]") or not info or info.mode ~= "file" then
            finish(s, "select exactly one existing file (not a folder)")
            return
        end
        s.path, s.phase = path, "closing"
        s.deadline = hs.timer.secondsSinceEpoch() + 5
    elseif s.phase == "closing" then
        -- The command exits before ghostty-window closes its terminal. Focusing
        -- the dialog earlier races that close, which can reactivate Ghostty.
        if not s.pickerAX or s.pickerAX:isValid() then return end
        focusOriginal(s)
        if not s.path then finish(s); return end
        s.phase = "focusing"
        s.deadline = hs.timer.secondsSinceEpoch() + 3
    elseif s.phase == "focusing" then
        local win = hs.window.focusedWindow()
        if not frontmost(s) or not win or win:id() ~= s.win:id() then return end
        hs.eventtap.keyStroke({ "cmd", "shift" }, "g", 0)
        s.phase = "opening-path"
        s.deadline = hs.timer.secondsSinceEpoch() + 3
    elseif s.phase == "opening-path" then
        local field = pathField(s)
        if not field then return end
        -- Write to this exact AX field, never a stream of global keystrokes
        -- that could leak into another app if focus changes mid-string.
        if not field:setAttributeValue("AXValue", s.path) then
            finish(s, "could not fill the native path field")
            return
        end
        s.field, s.phase = field, "typing-path"
    elseif s.phase == "typing-path" then
        local field = pathField(s)
        if field ~= s.field then finish(s, "focus changed; leaving the dialog alone"); return end
        if attr(field, "AXValue") ~= s.path then return end
        -- Exactly one Return: dismiss Go to Folder, not the final Open/Upload dialog.
        hs.eventtap.keyStroke({}, "return", 0)
        finish(s)
    end
end

local function shq(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

function M.start()
    if active then hs.alert.show("Yazi picker is already running", 1); return end
    local win = hs.window.focusedWindow()
    local root = win and hs.axuielement.windowElement(win)
    local panel = root and openPanel(root)
    local app = win and win:application()
    if not panel or not app then
        hs.alert.show("Yazi picker: open a native Open/Upload dialog first", 3)
        return
    end
    local s = { win = win, root = root, panel = panel, app = app,
        phase = "creating", deadline = hs.timer.secondsSinceEpoch() + 10 }
    active = s
    s.timer = hs.timer.doEvery(0.1, function() poll(s) end)
    s.task = hs.task.new("/usr/bin/mktemp", function(code, stdout)
        local dir = (stdout or ""):match("^([^\n]+)\n?$")
        if active ~= s then if code == 0 then clean(dir) end; return end
        if code ~= 0 or not dir then finish(s, "could not create a private chooser directory"); return end
        s.dir, s.phase = dir, "capturing"
        s.title = "YAZI PICKER " .. dir:match("[^/]+$")
        s.deadline = hs.timer.secondsSinceEpoch() + 10
        -- `status` is read-only in zsh. Expand $? directly, and publish only
        -- after the complete status has been written so polling cannot read it empty.
        local done = 'printf "%s\\n" "$?" > ' .. shq(dir .. "/done.tmp")
            .. "; /bin/mv " .. shq(dir .. "/done.tmp") .. " " .. shq(dir .. "/done")
        -- Keep a unique title until we have the actual chooser window's AX
        -- identity. A cold Ghostty launch creates a different initial window;
        -- the general first-window float heuristic cannot identify this one.
        local ready = shq(dir .. "/ready")
        local command = "trap " .. shq(done) .. " EXIT; printf '\\033]2;%s\\007' " .. shq(s.title)
            .. "; for ((i=0; i<100; i++)); do [[ -e " .. ready .. " ]] && break; /bin/sleep 0.1; done; "
            .. "[[ -e " .. ready .. " ]] || exit 1; yazi --chooser-file="
            .. shq(dir .. "/selection") .. " " .. shq(os.getenv("HOME"))
        local task = core.launchGhosttyWindow({
            title = s.title, command = command, float = 0.8,
            onExit = function(exitCode)
                if exitCode ~= 0 then finish(s, "could not launch Ghostty") end
            end,
        })
        if not task then finish(s, "could not launch Ghostty") end
    end, { "-d", hs.fs.temporaryDirectory() .. "yazi-picker.XXXXXXXX" })
    if not s.task or not s.task:start() then finish(s, "could not create a chooser directory") end
end

return M
