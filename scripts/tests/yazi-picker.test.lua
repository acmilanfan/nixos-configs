-- Run in Hammerspoon (no real windows or keyboard events are changed):
-- hs -c 'return dofile("/absolute/repo/scripts/tests/yazi-picker.test.lua")'
local root = debug.getinfo(1, "S").source:sub(2):match("^(.*)/scripts/tests/")
local modulePath = root .. "/dotfiles/hammerspoon/nanowm/yazi-picker.lua"
assert(hs.fs.attributes(modulePath), "Yazi picker module is not implemented")

local realHS = hs
local base = os.getenv("HOME") .. "/ai/artifacts/nixos-configs/yazi-picker-tests"
realHS.fs.mkdir(base)
local passed = 0

local function fixture()
    local dir = base .. "/" .. realHS.host.uuid()
    assert(realHS.fs.mkdir(dir))
    local f = { dir = dir, now = 0, timers = {}, keys = {}, text = {}, alerts = {}, launches = {} }
    local function element(attrs)
        return setmetatable({
            valid = true,
            attributeValue = function(self, name) return attrs[name] end,
            isValid = function(self) return self.valid end,
        }, { __index = attrs })
    end
    f.panel = element({ AXIdentifier = "open-panel", AXRole = "AXWindow" })
    f.terminal = element({ AXRole = "AXWindow" })
    f.terminal.valid = false
    f.go = element({ AXIdentifier = "GoToWindow", AXRole = "AXSheet", AXParent = f.panel })
    f.field = element({ AXIdentifier = "PathTextField", AXRole = "AXTextField", AXParent = f.go })
    f.field.setAttributeValue = function(self, name, value)
        assert(name == "AXValue")
        if f.failSet then return nil end
        f.text[#f.text + 1] = value
        self.attributeValue = function(object, key)
            if key == "AXValue" then return value end
            return object[key]
        end
        return self
    end
    f.app = { pid = function() return 42 end, name = function() return "TestApp" end }
    f.win = {
        id = function() return 123 end,
        application = function() return f.app end,
        focus = function(self) f.focused = self; f.frontmost = f.app end,
    }
    f.focused, f.frontmost = f.win, f.app
    local system = element({})
    system.attributeValue = function(_, name)
        if name == "AXFocusedUIElement" then return f.focusedElement end
    end
    local fakeHS = {
        alert = { show = function(s) f.alerts[#f.alerts + 1] = s end },
        fs = {
            temporaryDirectory = function() return base .. "/" end,
            attributes = realHS.fs.attributes,
            rmdir = realHS.fs.rmdir,
        },
        window = { focusedWindow = function() return f.focused end },
        application = {
            frontmostApplication = function() return f.frontmost end,
            get = function() return { allWindows = function() return f.ghosttyWindows or { f.focused } end } end,
        },
        axuielement = {
            windowElement = function(win)
                if win:id() == 999 then return f.terminal end
                return f.root or f.panel
            end,
            systemWideElement = function() return system end,
        },
        timer = {
            secondsSinceEpoch = function() return f.now end,
            doEvery = function(_, callback)
                local t = { callback = callback, stop = function(self) self.stopped = true end }
                f.timers[#f.timers + 1] = t
                return t
            end,
        },
        eventtap = {
            keyStroke = function(mods, key)
                f.keys[#f.keys + 1] = table.concat(mods, "+") .. ":" .. key
                if key == "g" and not f.noGoField then f.focusedElement = f.field end
            end,
            keyStrokes = function() error("paths must be written to the exact AX field, not globally typed") end,
        },
        task = { new = function(bin, callback, args)
            assert(bin == "/usr/bin/mktemp", "unexpected task: " .. bin)
            assert(args[1] == "-d")
            return { start = function(self)
                if not f.deferTemp then callback(0, dir .. "\n", "") end
                f.tempCallback = callback
                return self
            end }
        end },
    }
    local state = {}
    local core = { launchGhosttyWindow = function(opts)
        f.launches[#f.launches + 1] = opts
        f.focused = { id = function() return 999 end, title = function() return opts.title end }
        f.frontmost = { pid = function() return 99 end }
        if opts.onWindow then opts.onWindow(f.focused) end
        return true
    end, floatCentered = function() end }
    f.core = core
    local env = setmetatable({ hs = fakeHS, require = function(name)
        if name == "nanowm.core" then return core end
        if name == "nanowm.state" then return state end
        error("unexpected require: " .. name)
    end }, { __index = _G })
    f.picker = assert(loadfile(modulePath, "t", env))()
    function f.bindKeys(windows)
        local bindings = {}
        fakeHS.hotkey = {
            bind = function(mods, key, fn) bindings[table.concat(mods, "+") .. ":" .. key] = fn end,
            modal = { new = function() return { bind = function() end } end },
        }
        local config = { home = function() return os.getenv("HOME") end, modifiers = {
            alt = { "alt" }, altShift = { "alt", "shift" }, ctrlAlt = { "ctrl", "alt" },
            ctrlAltShift = { "ctrl", "alt", "shift" }, cmdAlt = { "cmd", "alt" },
            cmdAltShift = { "cmd", "alt", "shift" }, cmdAltShiftCtrl = { "cmd", "alt", "shift", "ctrl" },
        } }
        local modules = {
            ["nanowm.config"] = config, ["nanowm.core"] = core, ["nanowm.state"] = state,
            ["nanowm.yazi-picker"] = f.picker,
            ["nanowm.watchers"] = { getManagedWindows = function() return windows end },
            ["nanowm.actions"] = { bringWindowToCurrentContext = function(win) f.brought = win end },
        }
        local keyEnv = setmetatable({ hs = fakeHS, require = function(name) return modules[name] or {} end }, { __index = _G })
        assert(loadfile(root .. "/dotfiles/hammerspoon/nanowm/keybinds.lua", "t", keyEnv))().setup()
        return bindings
    end
    function f.write(name, contents)
        local file = assert(io.open(dir .. "/" .. name, "wb"))
        file:write(contents); file:close()
    end
    function f.tick(count)
        for _ = 1, count or 1 do
            f.now = f.now + 0.1
            for _, t in ipairs(f.timers) do if not t.stopped then t.callback() end end
        end
    end
    function f.finish(selection, code)
        if selection then f.write("selection", selection) end
        f.write("done", tostring(code or 0))
        f.tick(10)
    end
    function f.cleanup()
        f.now = f.now + 3600; f.tick()
        for _, name in ipairs({ "selection", "done", "done.tmp", "ready" }) do os.remove(dir .. "/" .. name) end
        realHS.fs.rmdir(dir)
    end
    return f
end

local function test(name, body)
    local f = fixture()
    local ok, err = pcall(body, f)
    f.cleanup()
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
end

test("single selection is typed without confirming Open", function(f)
    f.picker.start()
    assert(#f.launches == 1 and f.launches[1].float == 0.8)
    f.finish(root .. "/AGENTS.md\n")
    assert(f.text[1] == root .. "/AGENTS.md" and #f.text == 1)
    assert(table.concat(f.keys, ",") == "cmd+shift:g,:return", "only Go to Folder is confirmed")
end)

test("ordinary windows do not launch a picker", function(f)
    f.panel.attributeValue = function() return nil end
    f.picker.start()
    assert(#f.launches == 0 and #f.alerts > 0)
end)

test("attached Open sheets work even when AXSheets is empty", function(f)
    f.root = { attributeValue = function(_, name)
        if name == "AXSheets" then return {} end
        if name == "AXChildren" then return { f.panel } end
    end }
    f.picker.start()
    assert(#f.launches == 1, "attached Open sheet must be found")
end)

test("quitting without a selection leaves dialog untouched", function(f)
    f.picker.start(); f.finish(nil)
    assert(#f.text == 0 and #f.keys == 0)
    f.picker.start()
    assert(#f.launches == 2, "cancellation must release the picker")
end)

test("multiple files are rejected rather than silently picking one", function(f)
    f.picker.start(); f.finish(root .. "/AGENTS.md\n" .. root .. "/flake.nix\n")
    assert(#f.text == 0 and #f.keys == 0 and #f.alerts > 0)
end)

test("directories and missing files are rejected", function(f)
    f.picker.start(); f.finish(root .. "\n")
    assert(#f.text == 0 and #f.keys == 0 and #f.alerts > 0)
end)

test("missing files are rejected", function(f)
    f.picker.start(); f.finish(f.dir .. "/does-not-exist\n")
    assert(#f.text == 0 and #f.keys == 0 and #f.alerts > 0)
end)

test("spaces, quotes, and Unicode in filenames are preserved", function(f)
    local name = "space's $name ü.txt"
    f.write(name, "fixture")
    f.picker.start(); f.finish(f.dir .. "/" .. name .. "\n")
    os.remove(f.dir .. "/" .. name)
    assert(f.text[1] == f.dir .. "/" .. name)
end)

test("closed original dialog prevents any keystrokes", function(f)
    f.picker.start(); f.panel.valid = false; f.finish(root .. "/AGENTS.md\n")
    assert(#f.text == 0 and #f.keys == 0)
end)

test("missing Go to Folder field never receives text or Return", function(f)
    f.noGoField = true
    f.picker.start(); f.finish(root .. "/AGENTS.md\n"); f.tick(40)
    assert(#f.text == 0 and table.concat(f.keys, ",") == "cmd+shift:g")
end)

test("a path field belonging to another dialog is ignored", function(f)
    f.go.attributeValue = function() return nil end
    f.picker.start(); f.finish(root .. "/AGENTS.md\n"); f.tick(40)
    assert(#f.text == 0)
end)

test("duplicate presses do not open a second picker", function(f)
    f.picker.start(); f.picker.start()
    assert(#f.launches == 1)
end)

test("duplicate presses during temp creation are also blocked", function(f)
    f.deferTemp = true
    f.picker.start(); f.picker.start()
    f.tempCallback(0, f.dir .. "\n", "")
    assert(#f.launches == 1)
end)

test("focus stolen after typing never receives Return", function(f)
    f.picker.start()
    f.write("selection", root .. "/AGENTS.md\n"); f.write("done", "0")
    for _ = 1, 10 do if #f.text > 0 then break end; f.tick() end
    assert(#f.text == 1, "setup must reach the typed-path phase")
    f.frontmost = { pid = function() return 999 end }
    f.tick(10)
    assert(table.concat(f.keys, ",") == "cmd+shift:g")
end)

test("chooser timeout releases the shortcut", function(f)
    f.picker.start(); f.now = f.now + 1801; f.tick()
    assert(#f.text == 0 and #f.keys == 0 and #f.alerts > 0)
    assert(f.timers[1].stopped)
end)

test("mktemp failure does not launch Ghostty", function(f)
    f.deferTemp = true; f.picker.start()
    f.tempCallback(1, "", "failed")
    assert(#f.launches == 0 and #f.alerts > 0)
end)

test("launcher failure releases the picker without typing", function(f)
    f.picker.start(); f.launches[1].onExit(1, "", "launch failed")
    assert(#f.text == 0 and #f.keys == 0 and #f.alerts > 0)
end)

test("Yazi failure does not hand off a stale selection", function(f)
    f.picker.start(); f.finish(root .. "/AGENTS.md\n", 1)
    assert(#f.text == 0 and #f.keys == 0 and #f.alerts > 0)
end)

test("generated chooser command publishes real zsh exit status", function(f)
    f.picker.start()
    f.write("ready", "")
    local command = "function yazi { return 7; }; " .. f.launches[1].command
    local quoted = "'" .. command:gsub("'", "'\\''") .. "'"
    realHS.execute("/bin/zsh -fc " .. quoted)
    local file = io.open(f.dir .. "/done", "r")
    assert(file, "zsh EXIT trap must publish completion, even on failure")
    local code = file:read("*a"); file:close()
    assert(code == "7\n", "must preserve the Yazi exit status")
end)

test("picker identity survives title changes without excluding ordinary Yazi", function(f)
    assert(type(f.picker.isPickerWindow) == "function", "picker needs an identity check for Alt+Y")
    f.picker.start()
    local pickerWin = { id = function() return 999 end }
    f.tick(2)
    assert(f.picker.isPickerWindow(pickerWin))
    assert(not f.picker.isPickerWindow(f.win))
    f.finish(nil)
    assert(f.picker.isPickerWindow(pickerWin), "exclude picker until Ghostty finishes closing it")
end)

test("Alt+Y skips the chooser and focuses ordinary Yazi when both exist", function(f)
    local app = { name = function() return "Ghostty" end }
    local pickerWin = { id = function() return 999 end, title = function() return "Yazi: home" end,
        application = function() return app end }
    local normalWin = { id = function() return 456 end, title = function() return "Yazi: Downloads" end,
        application = function() return app end }
    local keys = f.bindKeys({ pickerWin, normalWin })
    keys["ctrl+alt:y"]()
    f.tick(2)
    keys["alt:y"]()
    assert(f.brought == normalWin, "Alt+Y must not focus the chooser")
    assert(#f.launches == 1, "Alt+Y should reuse the existing ordinary Yazi")
end)

test("handoff waits for Ghostty to close before returning focus", function(f)
    f.terminal.valid = true
    f.picker.start(); f.finish(root .. "/AGENTS.md\n")
    assert(#f.text == 0 and #f.keys == 0, "terminal closure must not steal focus during handoff")
    f.terminal.valid = false; f.tick(10)
    assert(f.text[1] == root .. "/AGENTS.md")
end)

test("cold Ghostty startup identifies chooser rather than initial window", function(f)
    f.terminal.valid = true
    local initial = { id = function() return 888 end, title = function() return "Ghostty" end }
    local chooser
    f.core.launchGhosttyWindow = function(opts)
        chooser = { id = function() return 999 end, title = function() return opts.title end }
        f.launches[#f.launches + 1] = opts
        f.ghosttyWindows = { initial, chooser }
        if opts.onWindow then opts.onWindow(initial) end
        return true
    end
    f.picker.start(); f.tick(2)
    assert(not f.picker.isPickerWindow(initial), "initial startup window is not the chooser")
    assert(f.picker.isPickerWindow(chooser), "actual chooser must be excluded from Alt+Y")
    f.finish(root .. "/AGENTS.md\n")
    assert(#f.keys == 0, "initial-window closure must not begin handoff while chooser is open")
    f.terminal.valid = false; f.tick(10)
    assert(f.text[1] == root .. "/AGENTS.md")
end)

test("failed native path write never confirms Go to Folder", function(f)
    f.failSet = true
    f.picker.start(); f.finish(root .. "/AGENTS.md\n")
    assert(#f.text == 0 and table.concat(f.keys, ",") == "cmd+shift:g")
    assert(#f.alerts > 0)
end)

return string.format("PASS: %d Yazi picker tests", passed)
