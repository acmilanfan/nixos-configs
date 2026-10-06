-- =============================================================================
-- NanoWM - A Tiling Window Manager for macOS
-- Version 40 - Modular Architecture
-- =============================================================================
--
-- This module orchestrates all NanoWM components:
--   config.lua      - Configuration and constants
--   state.lua       - State management and persistence
--   core.lua        - Core window management functions
--   layout.lua      - Layout engine and tiling
--   actions.lua     - Window actions (float, sticky, etc.)
--   tags.lua        - Tag navigation and management
--   menus.lua       - Chooser menus and UI
--   integrations.lua - Sketchybar, borders, battery saver
--   keybinds.lua    - All key bindings
--   watchers.lua    - Window filter event handlers
--
-- =============================================================================

local M = {}

-- Load all modules
local profiler = require("nanowm.profiler")
local config = require("nanowm.config")
local state = require("nanowm.state")
local core = require("nanowm.core")
local layout = require("nanowm.layout")
local actions = require("nanowm.actions")
local tags = require("nanowm.tags")
local menus = require("nanowm.menus")
local overview = require("nanowm.overview")
local integrations = require("nanowm.integrations")
local keybinds = require("nanowm.keybinds")
local watchers = require("nanowm.watchers")
local agents = require("nanowm.agents")

-- =============================================================================
-- Wire up module callbacks
-- =============================================================================

-- Layout completion triggers integration updates
layout.onTileComplete = function()
    integrations.updateSketchybar()
    tags.updateBorder()  -- special-tag backdrop holes follow the windows just placed
end

-- hammerspoon://nanowm?cmd=... is the entry point for shell callers (sketchybar clicks,
-- tmux agent hooks): `open -g "hammerspoon://nanowm?cmd=gotoTag&tag=3"`. Used instead of
-- `hs -c`, whose IPC port can wedge (a killed or overlapping client leaves it refusing
-- requests); URL events carry no per-client state. Parameters arrive URL-decoded.
local urlCommands = {
    gotoTag = function(p)
        local t = tonumber(p.tag)
        if t then tags.gotoTag(t) end
    end,
    toggleSpecial = function() tags.toggleSpecial() end,
    keybindMenu = function() menus.showKeybindMenu() end,
    focusAgent = function(p)
        if p.pane and p.pane ~= "" then agents.focusAgent(p.pane) end
    end,
    agentState = function(p) agents.onAgentStateChange(p.state, p.name) end,
    -- Run the regression suite (nanowm/spec.lua) and write its report to a file, for callers
    -- that can't read the HS console: open -g "hammerspoon://nanowm?cmd=spec", then read
    -- ~/.hammerspoon/nanowm_spec_report.txt (the suite's watchdog reports within ~30 s).
    spec = function()
        local spec = require("nanowm.spec")
        local out = config.home() .. "/.hammerspoon/nanowm_spec_report.txt"
        os.remove(out)
        spec.run()
        local tries = 0
        if M._specPoll then M._specPoll:stop() end
        M._specPoll = hs.timer.doEvery(1, function()  -- anchored on M so it isn't GC'd
            tries = tries + 1
            if spec.report or tries > 45 then
                M._specPoll:stop()
                M._specPoll = nil
                local f = io.open(out, "w")
                if f then
                    f:write(spec.report or "no report after 45 s; see the Hammerspoon console\n")
                    f:close()
                end
            end
        end)
    end,
    -- The caps-lock bar item asks for the current state when it has none (bar reload).
    capsLock = function()
        hs.task.new(config.sketchybarBin, nil, { "--trigger", "caps_lock_update",
            "STATE=" .. (hs.hid.capslock.get() and "on" or "off") }):start()
    end,
}
hs.urlevent.bind("nanowm", function(_, params)
    local cmd = urlCommands[params and params.cmd or ""]
    if cmd then
        cmd(params)
    else
        print("[NanoWM] unknown URL command: " .. tostring(params and params.cmd))
    end
end)

-- Tag changes trigger integration updates
tags.onTagChange = function()
    integrations.updateSketchybarNow()
end

-- =============================================================================
-- Public API (for backwards compatibility and external access)
-- =============================================================================

-- Re-export commonly used functions
M.config = config
M.state = state
M.overview = overview
M.profiler = profiler

-- Core functions
M.isFloating = core.isFloating
M.registerWindow = core.registerWindow
M.getTiledWindows = core.getTiledWindows
M.getAllVisibleWindows = core.getAllVisibleWindows
M.launchTask = core.launchTask

-- Layout functions
M.tile = layout.tile
M.raiseFloating = layout.raiseFloating

-- Action functions
M.toggleFloat = actions.toggleFloat
M.toggleSticky = actions.toggleSticky
M.toggleFullscreen = actions.toggleFullscreen
M.cycleFocus = actions.cycleFocus
M.swapWindow = actions.swapWindow
M.centerWindow = actions.centerWindow
M.resizeFloatingTo60 = actions.resizeFloatingTo60
M.resizeFloatingWindow = actions.resizeFloatingWindow
M.moveFloatingWindow = actions.moveFloatingWindow
M.toggleGaps = actions.toggleGaps
M.toggleCaffeinate = actions.toggleCaffeinate

function M.toggleOverview()
    if state.overviewActive then
        overview.hide()
    else
        overview.show()
    end
end

-- Tag functions
M.gotoTag = tags.gotoTag
M.togglePrevTag = tags.togglePrevTag
M.toggleSpecial = tags.toggleSpecial
M.moveWindowToTag = tags.moveWindowToTag
M.toggleFreeMode = tags.toggleFreeMode
M.markTagUrgent = tags.markTagUrgent
M.clearUrgent = tags.clearUrgent
M.gotoUrgent = tags.gotoUrgent
M.saveCurrentWindowTag = tags.saveCurrentWindowTag
M.saveAllWindowTags = tags.saveAllWindowTags
M.updateBorder = tags.updateBorder

-- Menu functions
M.openMenu = menus.openMenu
M.triggerMenuPalette = menus.triggerMenuPalette
M.showKeybindMenu = menus.showKeybindMenu

-- AI agent functions
M.showAgentMenu = agents.showMenu
M.focusAgent    = agents.focusAgent

-- Integration functions
M.updateSketchybar = integrations.updateSketchybar
M.toggleSketchybar = integrations.toggleSketchybar
M.toggleBatterySaver = integrations.toggleBatterySaver
M.startTimer = integrations.startTimer
M.showTimerRemaining = integrations.showTimerRemaining
M.cancelTimer = integrations.cancelTimer

-- State accessors (for backwards compatibility)
M.tags = state.tags
M.stacks = state.stacks
M.sticky = state.sticky
M.currentTag = state.currentTag
M.special = state.special
M.triggerSave = state.triggerSave
M.getMasterWidth = state.getMasterWidth
M.setMasterWidth = state.setMasterWidth
M.isTagFree = state.isTagFree

-- =============================================================================
-- Initialization
-- =============================================================================

function M.init()
    -- Profiling is opt-in and off by default; both calls no-op when disabled.
    -- Enable with: hs.settings.set("nanowm_profiler", true); hs.reload()
    if profiler.enabled then
        -- Patch os.execute / hs.execute globally so every blocking call is logged.
        profiler.patchGlobals()
        -- Heartbeat: logs "*** FREEZE ***" whenever Lua was blocked > 2s.
        profiler.startHeartbeat()
        print("[NanoWM] profiler ENABLED — globals patched, logging to nanowm_slow.log")
    end

    -- Disable window animations for instant tiling and better performance
    hs.window.animationDuration = 0

    -- Load persisted state
    state.load()

    -- Restore caffeinate state
    if state.caffeinateActive then
        hs.caffeinate.set("displayIdle", true, true)
        local status = "on"
        hs.task.new("/bin/zsh", nil, { "-c", "sketchybar --trigger nanowm_caffeinate STATE=" .. status }):start()
    end

    -- Setup window watchers
    watchers.setup()

    -- Setup keybindings
    keybinds.setup()

    -- Initialize integrations
    integrations.init()

    -- Initial tile
    layout.tile()

    -- Show startup message
    hs.alert.show("NanoWM " .. config.VERSION .. " Started")
end

return M
