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
