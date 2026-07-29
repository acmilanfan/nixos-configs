-- =============================================================================
-- NanoWM State Management
-- Handles persistence, state initialization, and save/load operations
-- =============================================================================

local config = require("nanowm.config")
local profiler = require("nanowm.profiler")

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

-- Reconcile persisted per-window state against reality.
--
-- This used to probe hs.window(id) for every entry in M.tags "to be extra safe", and never
-- actually removed anything from M.tags. Both halves of that were bad: a hs.window(id) lookup
-- for an id that no longer exists costs ~37 ms (measured), and since dead ids were never
-- dropped the table only grew — 800 entries, i.e. ~29 s of solid main-thread blocking, once
-- an hour. That matched the observed hourly freezes (24.1 s / 28.1 s / 29.0 s) almost exactly,
-- and it got worse the longer the config ran.
--
-- Now: build the live id set with a bounded number of enumerations, then drop state for ids
-- absent on two consecutive sweeps. The two-strike rule matters because tags are
-- user-meaningful — a transient AX hiccup must not destroy real tag assignments.
-- Interval is 900 s, not the original 3600 s: the hour was only defensible while the sweep
-- cost ~29 s. At ~50 ms there is no reason to wait, and with PRUNE_STRIKES = 2 this bounds
-- reclamation of a leaked id at ~30 min instead of ~2 h.
local _pruneStrikes = {}
local PRUNE_STRIKES = 2
local PRUNE_INTERVAL = 900

M.pruneTimer = hs.timer.new(PRUNE_INTERVAL, function()
    local watchers = require("nanowm.watchers")
    -- Don't enumerate while AX is known-slow; the sweep can wait an hour.
    if watchers.axBlocked and watchers.axBlocked() then return end

    local liveIds = {}
    for _, win in ipairs(watchers.getManagedWindows()) do
        local id = win:id()
        if id then liveIds[id] = true end
    end

    -- One global enumeration (~50 ms, hourly) instead of one lookup per id. Needed on top of
    -- _trackedWins because that set drops minimized windows, and a minimized window must not
    -- lose its tag.
    local t0 = hs.timer.secondsSinceEpoch()
    local allWins = hs.window.allWindows()
    local dt = hs.timer.secondsSinceEpoch() - t0
    if profiler.enabled and dt >= profiler.threshold then
        profiler.log("prune allWindows()", dt)
    end
    for _, win in ipairs(allWins) do
        local id = win:id()
        if id then liveIds[id] = true end
    end

    -- If AX returned nothing at all, treat it as unreliable rather than wiping state.
    if next(liveIds) == nil then return end

    local removed = 0
    for id in pairs(M.tags) do
        if liveIds[id] then
            _pruneStrikes[id] = nil
        else
            local strikes = (_pruneStrikes[id] or 0) + 1
            _pruneStrikes[id] = strikes
            if strikes >= PRUNE_STRIKES then
                local idStr = tostring(id)
                M.tags[id] = nil
                M.sticky[id] = nil
                M.floatingOverrides[id] = nil
                M.windowState[id] = nil
                M.windowWidths[id] = nil
                M.floatingCache[idStr] = nil
                M.sizeCache[idStr] = nil
                M.fullscreenCache[idStr] = nil
                _pruneStrikes[id] = nil
                removed = removed + 1
            end
        end
    end

    -- Drop references to ids that no longer have a tag.
    for _, stack in pairs(M.stacks) do
        for i = #stack, 1, -1 do
            if not M.tags[stack[i]] then table.remove(stack, i) end
        end
    end
    for _, order in pairs(M.tagCreationOrder) do
        for i = #order, 1, -1 do
            if not M.tags[order[i]] then table.remove(order, i) end
        end
    end
    for tag, id in pairs(M.tagLastFocused) do
        if not M.tags[id] then M.tagLastFocused[tag] = nil end
    end
    for _, positions in pairs(M.freeTagPositions) do
        for id in pairs(positions) do
            if not M.tags[id] then positions[id] = nil end
        end
    end

    -- Caches are keyed by string id and cheap to rebuild, so no strike protection needed.
    for idStr in pairs(M.floatingCache) do
        if not liveIds[tonumber(idStr) or -1] then M.floatingCache[idStr] = nil end
    end
    for idStr in pairs(M.sizeCache) do
        if not liveIds[tonumber(idStr) or -1] then M.sizeCache[idStr] = nil end
    end

    -- Caps for tag memory
    -- NOTE: still a destructive wipe rather than an LRU eviction — see M2 in the review.
    local keys = {}
    for k, _ in pairs(M.appTagMemory) do table.insert(keys, k) end
    if #keys > 1000 then
        M.appTagMemory = {}
    end

    if removed > 0 then
        print(string.format("[NanoWM] prune: dropped state for %d stale window ids", removed))
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

local function _home()
    local h = os.getenv("HOME") or ""
    if h:match("^/Users/") then return h end
    return "/Users/" .. (os.getenv("USER") or "gentooway")
end
local SAVE_FILE = _home() .. "/.hammerspoon/nanowm_state.json"

local saveTimer = hs.timer.delayed.new(2.0, profiler.wrap("state.saveTimer", function()
    M.save()
end))

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
    local t0 = profiler.enabled and hs.timer.secondsSinceEpoch() or 0
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
    local encodeT0 = profiler.enabled and hs.timer.secondsSinceEpoch() or 0
    local ok, json = pcall(hs.json.encode, data)
    local encodeDt = (profiler.enabled and hs.timer.secondsSinceEpoch() or 0) - encodeT0
    if ok and json then
        local writeT0 = profiler.enabled and hs.timer.secondsSinceEpoch() or 0
        local f = io.open(SAVE_FILE, "w")
        if f then
            f:write(json)
            f:close()
        end
        local writeDt = (profiler.enabled and hs.timer.secondsSinceEpoch() or 0) - writeT0
        if profiler.enabled and (encodeDt + writeDt) >= profiler.threshold then
            profiler.log("state.save", encodeDt + writeDt,
                string.format("encode:%.1fms write:%.1fms", encodeDt*1000, writeDt*1000))
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
