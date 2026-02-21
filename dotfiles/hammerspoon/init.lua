-- =============================================================================
-- Hammerspoon Configuration
-- =============================================================================
-- Emergency Rescue: CMD+ALT+CTRL+0 unhides all windows
-- =============================================================================

hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "0", function()
    hs.alert.show("🚨 Emergency Rescue Initiated 🚨")
    local wins = hs.window.allWindows()
    local screen = hs.screen.mainScreen():frame()
    for _, win in ipairs(wins) do
        win:setFrame({
            x = screen.x + 50,
            y = screen.y + 50,
            w = screen.w - 100,
            h = screen.h - 100,
        })
        win:raise()
    end
end)

-- =============================================================================
-- External Modules
-- =============================================================================

-- macOS Vim Navigation
require("macos-vim-navigation/init")

-- AClock Spoon
local clock = hs.loadSpoon("AClock")

-- VimMode Spoon
local VimMode = hs.loadSpoon("VimMode")
local vim = VimMode:new()
vim:bindHotKeys({ enter = { { "alt" }, "e" } })

-- =============================================================================
-- Base Settings
-- =============================================================================

hs.window.animationDuration = 0
hs.ipc.cliInstall()

-- =============================================================================
-- NanoWM - Tiling Window Manager
-- =============================================================================

local NanoWM = require("nanowm")
NanoWM.init()

-- Export NanoWM globally for console access and compatibility
_G.NanoWM = NanoWM

-- =============================================================================
-- AClock Toggle
-- =============================================================================

hs.hotkey.bind({ "cmd", "alt" }, "t", function()
    if clock then
        if clock.toggleShow then
            clock:toggleShow()
        elseif clock.show and clock.hide then
            if clock.canvas and clock.canvas:isShowing() then
                clock:hide()
            else
                clock:show()
            end
        else
            hs.alert.show("AClock method not found")
        end
    else
        hs.alert.show("AClock not loaded")
    end
end)

-- =============================================================================
-- Language Switcher (Universal: Ctrl+Shift+Space)
-- =============================================================================

local function cycleInputSource()
    local current = hs.keycodes.currentSourceID()
    local all_layouts = hs.keycodes.layouts(true) or {}
    local all_methods = hs.keycodes.methods(true) or {}

    local sources = {}
    local seen = {}
    local function add_source(s)
        if s and not seen[s] and not s:find("CharacterPalette") and not s:find("InkInput") then
            table.insert(sources, s)
            seen[s] = true
        end
    end

    for _, s in ipairs(all_layouts) do add_source(s) end
    for _, s in ipairs(all_methods) do add_source(s) end

    if #sources <= 1 then
        hs.alert.show("Only one input source available", 0.5)
        return
    end

    local nextIndex = 1
    for i, source in ipairs(sources) do
        if source == current then
            nextIndex = (i % #sources) + 1
            break
        end
    end

    local nextSource = sources[nextIndex]
    if nextSource then
        hs.keycodes.currentSourceID(nextSource)
        -- Show a cleaner name (e.g., "US" instead of "com.apple.keylayout.US")
        local cleanName = nextSource:match("[^.]*$")
        hs.alert.show("Input: " .. cleanName, 0.5)
    end
end

hs.hotkey.bind({ "ctrl", "shift" }, "space", cycleInputSource)
