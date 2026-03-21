-- =============================================================================
-- NanoWM Menus and UI
-- Chooser menus, command palette, and window switcher
-- =============================================================================

local config = require("nanowm.config")
local state = require("nanowm.state")
local core = require("nanowm.core")
local layout = require("nanowm.layout")
local tags = require("nanowm.tags")
local integrations = require("nanowm.integrations")

local M = {}

-- =============================================================================
-- Main Menu Chooser
-- =============================================================================

local menu = hs.chooser.new(function(choice)
    if not choice then return end
    local func = state.actionsCache[choice.uuid]
    if func then func() end
end)
menu:width(40)
menu:bgDark(true)
menu:fgColor({ hex = "#FFFFFF" })
menu:subTextColor({ hex = "#CCCCCC" })

function M.openMenu(mode)
    state.actionsCache = {}
    local choices = {}
    local idx = 1

    if mode == "commands" then
        local commands = {
            { t = "Reload Config", fn = hs.reload },
            { t = "Reset Layout", fn = layout.tile },
            {
                t = "Cycle Layout",
                fn = function()
                    actions.toggleLayout()
                end,
            },
            { t = "Toggle Free Mode (current tag)", fn = tags.toggleFreeMode },
            {
                t = "Show Tag Memory",
                fn = function()
                    local count = 0
                    local msg = "Tag Memory:\n"
                    for key, tag in pairs(state.appTagMemory) do
                        count = count + 1
                        if count <= 10 then
                            msg = msg .. "Tag " .. tostring(tag) .. ": " .. string.sub(key, 1, 40) .. "...\n"
                        end
                    end
                    msg = msg .. "\nTotal: " .. count .. " entries"
                    hs.alert.show(msg, 5)
                end,
            },
            {
                t = "Clear Tag Memory",
                fn = function()
                    state.appTagMemory = {}
                    state.triggerSave()
                    hs.alert.show("Tag memory cleared")
                end,
            },
            {
                t = "Reset Tags",
                fn = function()
                    state.resetAll()
                    hs.reload()
                end,
            },
            {
                t = "Kanata: Standard Mode",
                fn = function()
                    integrations.switchKanata("default")
                end,
            },
            {
                t = "Kanata: Home Row Mods Mode",
                fn = function()
                    integrations.switchKanata("homerow")
                end,
            },
            {
                t = "Kanata: Split Layout Mode",
                fn = function()
                    integrations.switchKanata("split")
                end,
            },
            {
                t = "Kanata: Angle Mod Mode",
                fn = function()
                    integrations.switchKanata("angle")
                end,
            },
        }

        for _, cmd in ipairs(commands) do
            local idStr = tostring(idx)
            table.insert(choices, { text = cmd.t, uuid = idStr })
            state.actionsCache[idStr] = cmd.fn
            idx = idx + 1
        end
        menu:placeholderText("NanoWM Commands")

    elseif mode == "windows" then
        local wins = hs.window.allWindows()
        for _, win in ipairs(wins) do
            if win and win:application() and win:isVisible() then
                local appName = win:application():name() or "?"
                local winTitle = win:title() or ""
                local tag = state.tags[win:id()] or "?"
                local extra = ""

                if state.sticky[win:id()] then
                    extra = " [STICKY]"
                end
                if core.isFloating(win) then
                    extra = extra .. " [FLOAT]"
                end

                local image = nil
                pcall(function()
                    image = hs.image.imageFromAppBundle(win:application():bundleID())
                end)

                local idStr = tostring(idx)
                table.insert(choices, {
                    text = appName,
                    subText = winTitle .. " [Tag " .. tag .. "]" .. extra,
                    image = image,
                    uuid = idStr,
                })

                state.actionsCache[idStr] = function()
                    local t = state.tags[win:id()]
                    if t and t ~= state.currentTag then
                        if t == "special" then
                            if not state.special.active then
                                tags.toggleSpecial()
                            end
                        else
                            tags.gotoTag(t)
                        end
                    end
                    hs.timer.doAfter(0.1, function()
                        win:focus()
                    end)
                end
                idx = idx + 1
            end
        end
        menu:placeholderText("Switch Window...")
    end

    menu:choices(choices)
    menu:show()
end

function M.openKanataMenu()
    state.actionsCache = {}
    local choices = {
        {
            text = "Home Row Mods + Layers",
            subText = (state.kanataMode == "homerow") and "ACTIVE" or "Switch to home row mods and layers",
            uuid = "homerow",
        },
        {
            text = "Split Layout (Experimental)",
            subText = (state.kanataMode == "split") and "ACTIVE" or "Home row on QWERTY, ZXCV as thumbs",
            uuid = "split",
        },
        {
            text = "Standard Mode",
            subText = (state.kanataMode == "default") and "ACTIVE" or "Switch to standard keyboard behavior",
            uuid = "default",
        },
        {
            text = "Angle Mod Layout",
            subText = (state.kanataMode == "angle") and "ACTIVE" or "Shift bottom row keys to the left",
            uuid = "angle",
        },
        {
            text = "Disabled Mode",
            subText = (state.kanataMode == "disabled") and "ACTIVE" or "Block all internal keyboard input",
            uuid = "disabled",
        },
    }

    local kanataChooser = hs.chooser.new(function(choice)
        if not choice then return end
        integrations.switchKanata(choice.uuid)
    end)
    kanataChooser:width(30)
    kanataChooser:bgDark(true)
    kanataChooser:choices(choices)
    kanataChooser:placeholderText("Select Kanata Mode")
    kanataChooser:show()
end

-- =============================================================================
-- Menu Walker (App Menu Palette)
-- =============================================================================

local walker = {}
walker.stack = {}
walker.chooser = hs.chooser.new(function(choice)
    if not choice then
        if #walker.stack > 0 then
            local parent = table.remove(walker.stack)
            walker.show(parent)
        end
        return
    end

    local item = state.actionsCache[choice.uuid]
    if item.menu then
        table.insert(walker.stack, walker.currentTable)
        walker.show(item.menu)
    else
        hs.application.frontmostApplication():selectMenuItem(item.title)
    end
end)
walker.chooser:width(40)
walker.chooser:bgDark(true)
walker.chooser:fgColor({ hex = "#FFFFFF" })
walker.chooser:subTextColor({ hex = "#CCCCCC" })

function walker.show(menuTable)
    walker.currentTable = menuTable
    state.actionsCache = {}
    local choices = {}
    local idx = 1

    if not menuTable then return end

    for _, item in pairs(menuTable) do
        if type(item) == "table" and item.title and #item.title > 0 then
            local idStr = tostring(idx)
            local entry = { text = item.title, uuid = idStr }
            if item.menu then
                entry.text = item.title .. " ▸"
                entry.subText = "Submenu"
            end
            table.insert(choices, entry)
            state.actionsCache[idStr] = item
            idx = idx + 1
        end
    end

    walker.chooser:choices(choices)
    walker.chooser:show()
end

function M.triggerMenuPalette()
    local app = hs.application.frontmostApplication()
    if app then
        local menuStruct = app:getMenuItems()
        if menuStruct then
            walker.stack = {}
            walker.show(menuStruct)
        else
            hs.alert.show("No menus found")
        end
    end
end

-- =============================================================================
-- Keybind Help Menu
-- =============================================================================

function M.showKeybindMenu()
    -- Import actions lazily to avoid circular dependency
    local actions = require("nanowm.actions")

    state.actionsCache = {}
    local keybinds = {
        {
            category = "Navigation",
            binds = {
                { key = "Alt+J", desc = "Focus next window", fn = function() actions.cycleFocus(1) end },
                { key = "Alt+K", desc = "Focus previous window", fn = function() actions.cycleFocus(-1) end },
                { key = "Alt+H", desc = "Decrease window/master size", fn = function() actions.adjustTiledSize("narrower") end },
                { key = "Alt+L", desc = "Increase window/master size", fn = function() actions.adjustTiledSize("wider") end },
            },
        },
        {
            category = "Window Management",
            binds = {
                { key = "Alt+Shift+J/K", desc = "Swap tiled window", fn = nil },
                { key = "Alt+Shift+H/L/J/K", desc = "Resize floating window", fn = nil },
                { key = "Alt+Shift+R", desc = "Cycle window size (scrolling layout)", fn = actions.cycleWindowSize },
                { key = "Alt+F", desc = "Toggle fullscreen", fn = actions.toggleFullscreen },
                { key = "Alt+C", desc = "Center window", fn = actions.centerWindow },
                { key = "Alt+Shift+C", desc = "Resize floating to 60%", fn = actions.resizeFloatingTo60 },
                { key = "Alt+Shift+Space", desc = "Toggle float", fn = actions.toggleFloat },
                { key = "Ctrl+Alt+Shift+S", desc = "Toggle sticky", fn = actions.toggleSticky },
                { key = "Alt+Shift+Q", desc = "Close window", fn = actions.closeWindow },
            },
        },
        {
            category = "Tags",
            binds = {
                { key = "Alt+1-9", desc = "Go to tag 1-9", fn = function() tags.gotoTag(1) end },
                { key = "Alt+0", desc = "Go to tag 10", fn = function() tags.gotoTag(10) end },
                { key = "Alt+Shift+1-9", desc = "Move window to tag", fn = nil },
                { key = "Alt+Escape", desc = "Toggle previous tag", fn = tags.togglePrevTag },
                { key = "Alt+S", desc = "Toggle special tag", fn = tags.toggleSpecial },
                { key = "Alt+Shift+S", desc = "Move to special tag", fn = function() tags.moveWindowToTag(state.special.tag) end },
                { key = "Alt+U", desc = "Go to urgent tag", fn = tags.gotoUrgent },
                { key = "Alt+Shift+M", desc = "Save window tag to memory", fn = tags.saveCurrentWindowTag },
            },
        },
        {
            category = "Layout & Display",
            binds = {
                { key = "Cmd+Space", desc = "Cycle layout (vertical/horizontal/mono/scrolling)", fn = actions.toggleLayout },
                { key = "Alt+G", desc = "Toggle gaps", fn = actions.toggleGaps },
                { key = "Ctrl+Alt+F", desc = "Toggle free mode", fn = tags.toggleFreeMode },
            },
        },
        {
            category = "Menus",
            binds = {
                { key = "Alt+M", desc = "App menu palette", fn = M.triggerMenuPalette },
                { key = "Alt+P", desc = "Commands menu", fn = function() M.openMenu("commands") end },
                { key = "Alt+I", desc = "Windows menu", fn = function() M.openMenu("windows") end },
                { key = "Alt+N", desc = "Control Center (Audio/WiFi/BT)", fn = function() M.openControlMenu() end },
                { key = "Alt+/", desc = "This keybind menu", fn = M.showKeybindMenu },
            },
        },
        {
            category = "Applications",
            binds = {
                { key = "Alt+Return", desc = "New Alacritty", fn = function() core.launchTask("/usr/bin/open", { "-n", "-a", "Alacritty" }) end },
                { key = "Alt+B", desc = "New Firefox", fn = function() core.launchTask("/usr/bin/open", { "-n", "-a", "Firefox" }) end },
                { key = "Alt+D", desc = "Launch Raycast", fn = function() hs.application.launchOrFocus("Raycast") end },
            },
        },
        {
            category = "AI Agents",
            binds = {
                { key = "Alt+A",      desc = "Agent chooser (focus running agent)", fn = function() require("nanowm.agents").showMenu() end },
                { key = "Ctrl+Alt+A", desc = "Toggle SketchyBar agent popup",       fn = function() hs.task.new("/bin/zsh", nil, { "-c", "sketchybar --set ai_agents popup.drawing=toggle 2>/dev/null" }):start() end },
            },
        },
        {
            category = "Leader Mode (Alt + ,)",
            binds = {
                { key = "a -> t/f/s", desc = "Apps: Term / Firefox / Slack", fn = function() end },
                { key = "s -> p/g/o", desc = "System: Power / Bar / Borders", fn = function() end },
                { key = "s -> k/l",   desc = "System: Kanata / Lock", fn = function() end },
                { key = "c -> m/a/w/b", desc = "Control: Mixer / Audio / WiFi / BT", fn = function() end },
                { key = "v",         desc = "Enter Vim Mode", fn = function() end },
                { key = "k",         desc = "Toggle HS Console", fn = function() end },
                { key = "r",         desc = "Reload Hammerspoon", fn = function() end },
                { key = "q / Esc",   desc = "Exit leader mode", fn = function() end },
            },
        },
        {
            category = "Integrations",
            binds = {
                { key = "Alt+Shift+G", desc = "Toggle sketchybar", fn = integrations.toggleSketchybar },
                { key = "Ctrl+Alt+B", desc = "Toggle borders", fn = integrations.toggleBorders },
                { key = "Ctrl+Alt+P", desc = "Toggle battery saver", fn = integrations.toggleBatterySaver },
                { key = "Ctrl+Alt+Shift+K", desc = "Kanata mode menu", fn = M.openKanataMenu },
            },
        },
        {
            category = "System",
            binds = {
                { key = "Ctrl+Alt+Shift+R", desc = "Reload config", fn = hs.reload },
                { key = "Ctrl+Alt+Shift+C", desc = "Toggle HS console", fn = hs.toggleConsole },
                { key = "Cmd+Alt+Shift+C", desc = "Toggle Caffeinate", fn = actions.toggleCaffeinate },
                { key = "Cmd+Alt+Shift+Ctrl+L", desc = "Lock Screen", fn = function() hs.caffeinate.lockScreen() end },
            },
        },
    }

    local choices = {}
    local idx = 1

    for _, section in ipairs(keybinds) do
        table.insert(choices, {
            text = "━━━ " .. section.category .. " ━━━",
            subText = "",
            uuid = "header_" .. section.category,
        })

        for _, bind in ipairs(section.binds) do
            local idStr = tostring(idx)
            table.insert(choices, {
                text = bind.key,
                subText = bind.desc,
                uuid = idStr,
            })
            if bind.fn then
                state.actionsCache[idStr] = bind.fn
            end
            idx = idx + 1
        end
    end

    local chooser = hs.chooser.new(function(choice)
        if not choice then return end
        local func = state.actionsCache[choice.uuid]
        if func then func() end
    end)
    chooser:width(50)
    chooser:bgDark(true)
    chooser:fgColor({ hex = "#FFFFFF" })
    chooser:subTextColor({ hex = "#CCCCCC" })
    chooser:choices(choices)
    chooser:placeholderText("Search keybinds (press Enter to execute)...")
    chooser:searchSubText(true)
    chooser:show()
end

-- =============================================================================
-- Control Center
-- =============================================================================

function M.openControlMenu()
    state.actionsCache = {}
    local choices = {
        {
            text = "Audio Center (Keyboard)",
            subText = "Switch devices and set volume via keyboard",
            uuid = "audio_center",
        },
        {
            text = "Audio Mixer (FineTune)",
            subText = "Launch/Toggle FineTune GUI (Per-app volume)",
            uuid = "audio_gui",
        },
        {
            text = "WiFi Control (wifitui)",
            subText = "Open TUI for WiFi management in Alacritty",
            uuid = "wifi",
        },
        {
            text = "Bluetooth Control (btui)",
            subText = "Open TUI for Bluetooth management in Alacritty",
            uuid = "bluetooth",
        },
    }

    local controlChooser = hs.chooser.new(function(choice)
        if not choice then return end

        if choice.uuid == "audio_center" then
            M.openAudioMenu()
        elseif choice.uuid == "audio_gui" then
            core.toggleFineTune()
        elseif choice.uuid == "wifi" then
            core.openInAlacritty("wifitui", 0.5)
        elseif choice.uuid == "bluetooth" then
            core.openInAlacritty("btui", 0.5)
        end
    end)

    controlChooser:width(30)
    controlChooser:bgDark(true)
    controlChooser:choices(choices)
    controlChooser:placeholderText("Control Center")
    controlChooser:show()
end

function M.openAudioMenu()
    state.actionsCache = {}
    local choices = {}

    -- Current Status Header
    local defaultOut = hs.audiodevice.defaultOutputDevice()
    if defaultOut then
        local curOut = defaultOut:name() or "Unknown"
        local curVol = math.floor(defaultOut:volume() or 0)
        local isMuted = defaultOut:muted()

        table.insert(choices, {
            text = "Current: " .. curOut,
            subText = string.format("Volume: %d%% %s", curVol, isMuted and "[MUTED]" or ""),
            uuid = "header",
            image = hs.image.imageFromName(isMuted and "NSStatusPartiallyAvailable" or "NSStatusAvailable")
        })
    else
        table.insert(choices, {
            text = "No default output device found",
            uuid = "header"
        })
    end

    -- Volume Controls
    local vols = {0, 25, 50, 75, 100}
    for _, v in ipairs(vols) do
        table.insert(choices, {
            text = "Set Volume: " .. v .. "%",
            subText = "Adjust system output volume",
            uuid = "vol_" .. v
        })
    end

    table.insert(choices, {
        text = "Toggle Mute",
        subText = "Toggle current output mute state",
        uuid = "toggle_mute"
    })

    -- All Devices
    local allDevices = hs.audiodevice.allDevices()

    -- Output Devices
    table.insert(choices, { text = "━━━ Output Devices ━━━", uuid = "sep_out" })
    for _, dev in ipairs(allDevices) do
        if dev:isOutputDevice() then
            table.insert(choices, {
                text = dev:name(),
                subText = "Switch output to " .. dev:name(),
                uuid = "out_" .. dev:uid()
            })
        end
    end

    -- Input Devices
    table.insert(choices, { text = "━━━ Input Devices ━━━", uuid = "sep_in" })
    for _, dev in ipairs(allDevices) do
        if dev:isInputDevice() then
            table.insert(choices, {
                text = dev:name(),
                subText = "Switch input to " .. dev:name(),
                uuid = "in_" .. dev:uid()
            })
        end
    end

    local audioChooser = hs.chooser.new(function(choice)
        if not choice or choice.uuid:match("^sep_") or choice.uuid == "header" then return end

        local outDev = hs.audiodevice.defaultOutputDevice()
        if choice.uuid:match("^vol_") and outDev then
            local v = tonumber(choice.uuid:match("vol_(%d+)"))
            outDev:setVolume(v)
            hs.alert.show("Volume set to " .. v .. "%")
        elseif choice.uuid == "toggle_mute" and outDev then
            outDev:setMuted(not outDev:muted())
            hs.alert.show(outDev:muted() and "Muted" or "Unmuted")
        elseif choice.uuid:match("^out_") then
            local uid = choice.uuid:sub(5)
            local dev = hs.audiodevice.findDeviceByUID(uid)
            if dev then
                dev:setDefaultOutputDevice()
                hs.alert.show("Output: " .. dev:name())
            end
        elseif choice.uuid:match("^in_") then
            local uid = choice.uuid:sub(4)
            local dev = hs.audiodevice.findDeviceByUID(uid)
            if dev then
                dev:setDefaultInputDevice()
                hs.alert.show("Input: " .. dev:name())
            end
        end
    end)

    audioChooser:width(35)
    audioChooser:bgDark(true)
    audioChooser:choices(choices)
    audioChooser:placeholderText("Audio Center")
    audioChooser:show()
end

return M
