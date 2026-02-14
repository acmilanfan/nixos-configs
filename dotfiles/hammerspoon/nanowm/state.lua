-- =============================================================================
-- NanoWM State Management
-- Handles persistence, state initialization, and save/load operations
-- =============================================================================

local config = require("nanowm.config")

local M = {}

-- Runtime state (not persisted directly, derived from windows)
M.tags = {}
M.stacks = {}
M.sticky = {}
M.floatingOverrides = {}
M.floatingCache = {}
M.sizeCache = {}
M.fullscreenCache = {}
M.windowState = {}
M.masterWidths = {}
M.tagFullscreenState = {}
M.tagLastFocused = {}
M.appTagMemory = {}
M.freeTags = {}
M.freeTagPositions = {}

-- Pending destruction tracking
M.pendingDestruction = {}

-- Current state
M.currentTag = 1
M.prevTag = 1
M.isFullscreen = false
M.layout = config.layout
M.gap = config.gap
M.caffeinateActive = false

-- Special tag state
M.special = {
    active = false,
    tag = config.specialTag,
    border = nil,
    raiseTimer = nil,
}

-- Guard state
M.focusTimer = nil
M.launching = false
M.tileTimer = nil

-- Timer tracking
M.activeTimer = nil
M.timerEndTime = nil
M.timerDuration = nil

-- Urgent tags (Awesome WM style)
M.urgentTags = {}
M.lastManualTagSwitch = 0
M.lastTileTime = 0

-- UI state
M.actionsCache = {}

-- Integration state
M.sketchybarEnabled = false
M.bordersEnabled = false
M.bordersCurrentlyShowing = false
M.batterySaverEnabled = false
M.batterySaverPreviousState = {}
M.kanataMode = "homerow"

-- =============================================================================
-- Persistence Functions
-- =============================================================================

local saveTimer = hs.timer.delayed.new(2.0, function()
    M.save()
end)

local function serialize(t)
    local out = {}
    for k, v in pairs(t or {}) do
        out[tostring(k)] = v
    end
    return out
end

local function clean(t)
    local out = {}
    for k, v in pairs(t or {}) do
        out[tonumber(k) or k] = v
    end
    return out
end

function M.load()
    M.tags = clean(hs.settings.get("nanoWM_tags"))
    M.stacks = clean(hs.settings.get("nanoWM_stacks"))
    M.sticky = clean(hs.settings.get("nanoWM_sticky"))
    M.floatingOverrides = clean(hs.settings.get("nanoWM_floatingOverrides"))
    M.floatingCache = hs.settings.get("nanoWM_floatingCache") or {}
    M.sizeCache = hs.settings.get("nanoWM_sizeCache") or {}
    M.fullscreenCache = hs.settings.get("nanoWM_fullscreenCache") or {}
    M.masterWidths = clean(hs.settings.get("nanoWM_masterWidths")) or {}
    M.tagFullscreenState = clean(hs.settings.get("nanoWM_tagFullscreenState")) or {}
    M.tagLastFocused = clean(hs.settings.get("nanoWM_tagLastFocused")) or {}
    M.appTagMemory = hs.settings.get("nanoWM_appTagMemory") or {}
    M.freeTags = clean(hs.settings.get("nanoWM_freeTags")) or {}

    M.currentTag = hs.settings.get("nanoWM_currentTag") or 1
    M.prevTag = hs.settings.get("nanoWM_prevTag") or 1
    M.sketchybarEnabled = hs.settings.get("nanoWM_sketchybarEnabled") or false
    M.bordersEnabled = hs.settings.get("nanoWM_bordersEnabled") or false
    M.kanataMode = hs.settings.get("nanoWM_kanataMode") or "homerow"
end

function M.save()
    hs.settings.set("nanoWM_tags", serialize(M.tags))
    hs.settings.set("nanoWM_stacks", serialize(M.stacks))
    hs.settings.set("nanoWM_sticky", serialize(M.sticky))
    hs.settings.set("nanoWM_floatingOverrides", serialize(M.floatingOverrides))
    hs.settings.set("nanoWM_floatingCache", M.floatingCache)
    hs.settings.set("nanoWM_sizeCache", M.sizeCache)
    hs.settings.set("nanoWM_fullscreenCache", M.fullscreenCache)
    hs.settings.set("nanoWM_masterWidths", serialize(M.masterWidths))
    hs.settings.set("nanoWM_tagFullscreenState", serialize(M.tagFullscreenState))
    hs.settings.set("nanoWM_tagLastFocused", serialize(M.tagLastFocused))
    hs.settings.set("nanoWM_currentTag", M.currentTag)
    hs.settings.set("nanoWM_prevTag", M.prevTag)
    hs.settings.set("nanoWM_appTagMemory", M.appTagMemory)
    hs.settings.set("nanoWM_sketchybarEnabled", M.sketchybarEnabled)
    hs.settings.set("nanoWM_bordersEnabled", M.bordersEnabled)
    hs.settings.set("nanoWM_freeTags", serialize(M.freeTags))
    hs.settings.set("nanoWM_kanataMode", M.kanataMode)
end

function M.triggerSave()
    saveTimer:start()
end

-- =============================================================================
-- Master Width Helpers
-- =============================================================================

function M.getMasterWidth(tag)
    tag = tag or M.currentTag
    return M.masterWidths[tag] or config.defaultMasterWidth
end

function M.setMasterWidth(tag, width)
    tag = tag or M.currentTag
    M.masterWidths[tag] = width
    M.triggerSave()
end

-- =============================================================================
-- Tag Memory Functions
-- =============================================================================

function M.getWindowKey(win)
    if not win then
        return nil
    end

    local app = win:application()
    if not app then
        return nil
    end

    local appName = app:name()
    local title = win:title() or ""

    if config.excludedFromTagMemory[appName] then
        return nil
    end
    if title == "" or title == "New Tab" or title == "Untitled" then
        return nil
    end

    -- Normalize title by removing common app suffixes
    local normalizedTitle = title
    normalizedTitle = string.gsub(normalizedTitle, " [-–—] Mozilla Firefox$", "")
    normalizedTitle = string.gsub(normalizedTitle, " [-–—] Google Chrome$", "")
    normalizedTitle = string.gsub(normalizedTitle, " [-–—] Safari$", "")
    normalizedTitle = string.gsub(normalizedTitle, " [-–—] Arc$", "")
    normalizedTitle = string.gsub(normalizedTitle, " [-–—] Slack$", "")
    normalizedTitle = string.gsub(normalizedTitle, " [-–—] Discord$", "")
    normalizedTitle = string.gsub(normalizedTitle, " [-–—] Code$", "")
    normalizedTitle = string.gsub(normalizedTitle, " [-–—] Visual Studio Code$", "")

    local shortTitle = string.sub(normalizedTitle, 1, 60)
    return appName .. "::" .. shortTitle
end

function M.rememberWindowTag(win, tag)
    local key = M.getWindowKey(win)
    if key then
        M.appTagMemory[key] = tag
        M.triggerSave()
    end
end

function M.getRememberedTag(win)
    local key = M.getWindowKey(win)
    if key and M.appTagMemory[key] then
        return M.appTagMemory[key]
    end
    return nil
end

-- =============================================================================
-- Free Mode Helpers
-- =============================================================================

function M.isTagFree(tag)
    tag = tag or (M.special.active and M.special.tag or M.currentTag)
    return M.freeTags[tag] == true
end

-- =============================================================================
-- Reset Functions
-- =============================================================================

function M.resetAll()
    M.tags = {}
    M.stacks = {}
    M.sticky = {}
    M.floatingOverrides = {}
    M.appTagMemory = {}
    M.freeTags = {}
    M.currentTag = 1
    M.triggerSave()
end

return M
