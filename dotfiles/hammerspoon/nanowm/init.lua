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
local config = require("nanowm.config")
local state = require("nanowm.state")
local core = require("nanowm.core")
local layout = require("nanowm.layout")
local actions = require("nanowm.actions")
local tags = require("nanowm.tags")
local menus = require("nanowm.menus")
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
    integrations.updateBordersVisibility()
end

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
M.toggleBorders = integrations.toggleBorders
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
    -- Load persisted state
    state.load()

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
