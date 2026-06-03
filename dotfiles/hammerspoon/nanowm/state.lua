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
M.windowWidths = {}
M.tagLayouts = {}
M.tagCreationOrder = {}
M.tagFullscreenState = {}
M.tagLastFocused = {}
M.appTagMemory = {}
M.freeTags = {}
M.freeTagPositions = {}
M.screenFrames = {}
M.tagSnapshots = {}
M.overviewActive = false

-- Initialize tag snapshots
for i = 1, 20 do M.tagSnapshots[i] = nil end
M.tagSnapshots["special"] = nil

-- Pending destruction tracking
M.pendingDestruction = {}

-- Current state
M.activeTags = { 1, 11, 21, 31 } -- Active tag per monitor index
M.currentTag = 1
M.prevTag = 1
M.isFullscreen = false
M.layout = config.layout
M.availableLayouts = { "vertical", "horizontal", "mono", "scrolling" }
M.gap = config.gap
M.caffeinateActive = false
M.weekenduoWinId = nil
M.weekenduoLaunching = false
M.markNextWeekenduo = false
M.lastIntendedFocusId = nil

-- Pruning function to prevent memory leaks
M.pruneTimer = hs.timer.new(3600, function()
    -- Only prune if we have managed windows tracked, otherwise it might be a weird state
    local managed = require("nanowm.watchers").getManagedWindows()
    if #managed == 0 then return end

    local validIds = {}
    for _, win in ipairs(managed) do
        validIds[tostring(win:id())] = true
    end

    -- Also include all windows currently on tags to be extra safe
    for id, _ in pairs(M.tags) do
        local w = hs.window(id)
        if w and w:id() then validIds[tostring(id)] = true end
    end

    for idStr, _ in pairs(M.floatingCache) do
        if not validIds[idStr] then M.floatingCache[idStr] = nil end
    end
    for idStr, _ in pairs(M.sizeCache) do
        if not validIds[idStr] then M.sizeCache[idStr] = nil end
    end

    -- Caps for tag memory
    local keys = {}
    for k, _ in pairs(M.appTagMemory) do table.insert(keys, k) end
    if #keys > 1000 then
        -- Simple clear if too large
        M.appTagMemory = {}
    end
    M.triggerSave()
end)
M.pruneTimer:start()

-- Special tag state
M.special = {
    active = false,
    tag = config.specialTag,
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
M.lastMove = nil -- { winId, fromTag, toTag }

-- UI state
M.actionsCache = {}

-- Integration state
M.sketchybarEnabled = false
M.batterySaverEnabled = false
M.batterySaverPreviousState = {}
M.kanataMode = "homerow"

-- Power state: true when running on AC, false on battery
-- Updated by the battery watcher in integrations.lua
M.acPower = hs.battery.powerSource() == "AC Power"

-- Returns the perf-profile table appropriate for the current power source
function M.perfProfile()
    return M.acPower and config.perf.ac or config.perf.battery
end

-- =============================================================================
-- Persistence Functions
-- =============================================================================

local SAVE_FILE = os.getenv("HOME") .. "/.hammerspoon/nanowm_state.json"

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

-- Two-level key conversion for freeTagPositions: {[tag][winId]=frame}
-- JSON round-trip turns numeric keys into strings at both levels.
local function cleanNested(t)
    local out = {}
    for k, v in pairs(t or {}) do
        local outerKey = tonumber(k) or k
        if type(v) == "table" then
            out[outerKey] = clean(v)
        else
            out[outerKey] = v
        end
    end
    return out
end

local function loadFromData(d)
    M.tags              = clean(d.tags)
    M.stacks            = clean(d.stacks)
    M.sticky            = clean(d.sticky)
    M.floatingOverrides = clean(d.floatingOverrides)
    M.floatingCache     = d.floatingCache or {}
    M.sizeCache         = d.sizeCache or {}
    M.fullscreenCache   = d.fullscreenCache or {}
    M.masterWidths      = clean(d.masterWidths) or {}
    M.windowWidths      = clean(d.windowWidths) or {}
    M.tagLayouts        = clean(d.tagLayouts) or {}
    M.tagCreationOrder  = clean(d.tagCreationOrder) or {}
    M.tagFullscreenState = clean(d.tagFullscreenState) or {}
    M.tagLastFocused    = clean(d.tagLastFocused) or {}
    M.appTagMemory      = d.appTagMemory or {}
    M.freeTags          = clean(d.freeTags) or {}
    M.freeTagPositions  = cleanNested(d.freeTagPositions) or {}
    M.activeTags        = clean(d.activeTags) or { 1, 11, 21, 31 }
    M.currentTag        = d.currentTag or 1
    M.prevTag           = d.prevTag or 1
    M.layout            = d.globalLayout or config.layout
    M.weekenduoWinId    = d.weekenduoWinId
    M.sketchybarEnabled = d.sketchybarEnabled or false
    M.bordersEnabled    = d.bordersEnabled or false
    M.kanataMode        = d.kanataMode or "homerow"
    M.caffeinateActive  = d.caffeinateActive or false
end

function M.load()
    -- Fast path: single JSON file read
    local f = io.open(SAVE_FILE, "r")
    if f then
        local raw = f:read("*a")
        f:close()
        local ok, data = pcall(hs.json.decode, raw)
        if ok and type(data) == "table" then
            loadFromData(data)
            return
        end
    end
    -- Fallback: migrate from hs.settings (first boot after upgrade)
    loadFromData({
        tags              = hs.settings.get("nanoWM_tags"),
        stacks            = hs.settings.get("nanoWM_stacks"),
        sticky            = hs.settings.get("nanoWM_sticky"),
        floatingOverrides = hs.settings.get("nanoWM_floatingOverrides"),
        floatingCache     = hs.settings.get("nanoWM_floatingCache"),
        sizeCache         = hs.settings.get("nanoWM_sizeCache"),
        fullscreenCache   = hs.settings.get("nanoWM_fullscreenCache"),
        masterWidths      = hs.settings.get("nanoWM_masterWidths"),
        windowWidths      = hs.settings.get("nanoWM_windowWidths"),
        tagLayouts        = hs.settings.get("nanoWM_tagLayouts"),
        tagCreationOrder  = hs.settings.get("nanoWM_tagCreationOrder"),
        tagFullscreenState = hs.settings.get("nanoWM_tagFullscreenState"),
        tagLastFocused    = hs.settings.get("nanoWM_tagLastFocused"),
        appTagMemory      = hs.settings.get("nanoWM_appTagMemory"),
        freeTags          = hs.settings.get("nanoWM_freeTags"),
        freeTagPositions  = hs.settings.get("nanoWM_freeTagPositions"),
        activeTags        = hs.settings.get("nanoWM_activeTags"),
        currentTag        = hs.settings.get("nanoWM_currentTag"),
        prevTag           = hs.settings.get("nanoWM_prevTag"),
        globalLayout      = hs.settings.get("nanoWM_globalLayout"),
        weekenduoWinId    = hs.settings.get("nanoWM_weekenduoWinId"),
        sketchybarEnabled = hs.settings.get("nanoWM_sketchybarEnabled"),
        bordersEnabled    = hs.settings.get("nanoWM_bordersEnabled"),
        kanataMode        = hs.settings.get("nanoWM_kanataMode"),
        caffeinateActive  = hs.settings.get("nanoWM_caffeinateActive"),
    })
end

function M.save()
    local data = {
        tags               = serialize(M.tags),
        stacks             = serialize(M.stacks),
        sticky             = serialize(M.sticky),
        floatingOverrides  = serialize(M.floatingOverrides),
        floatingCache      = M.floatingCache,
        sizeCache          = M.sizeCache,
        fullscreenCache    = M.fullscreenCache,
        masterWidths       = serialize(M.masterWidths),
        windowWidths       = serialize(M.windowWidths),
        tagLayouts         = serialize(M.tagLayouts),
        tagCreationOrder   = serialize(M.tagCreationOrder),
        tagFullscreenState = serialize(M.tagFullscreenState),
        tagLastFocused     = serialize(M.tagLastFocused),
        activeTags         = serialize(M.activeTags),
        currentTag         = M.currentTag,
        prevTag            = M.prevTag,
        globalLayout       = M.layout,
        weekenduoWinId     = M.weekenduoWinId,
        appTagMemory       = M.appTagMemory,
        sketchybarEnabled  = M.sketchybarEnabled,
        bordersEnabled     = M.bordersEnabled,
        freeTags           = serialize(M.freeTags),
        freeTagPositions   = M.freeTagPositions,
        kanataMode         = M.kanataMode,
        caffeinateActive   = M.caffeinateActive,
    }
    local ok, json = pcall(hs.json.encode, data)
    if ok and json then
        local f = io.open(SAVE_FILE, "w")
        if f then
            f:write(json)
            f:close()
        end
    end
end

function M.triggerSave()
    saveTimer:start()
end

-- =============================================================================
-- Layout Helpers
-- =============================================================================

function M.getLayout(tag)
    tag = tag or M.currentTag
    return M.tagLayouts[tag] or M.layout
end

function M.setLayout(tag, layoutName)
    tag = tag or M.currentTag
    M.tagLayouts[tag] = layoutName
    M.triggerSave()
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

function M.getScreenForTag(tag)
    local screens = hs.screen.allScreens()
    if #screens == 0 then return nil end

    if tag == M.special.tag then return screens[1] end

    local numTag = tonumber(tag)
    if not numTag then return screens[1] end

    if #screens == 1 then
        -- All tags on primary if only 1 screen
        return screens[1]
    else
        -- AwesomeWM style: fixed mapping if 2+ screens
        local monitorIdx = math.floor((numTag - 1) / 10) + 1
        if monitorIdx <= #screens then
            return screens[monitorIdx]
        end
    end
    return screens[1]
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
