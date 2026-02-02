-- =============================================================================
-- EMERGENCY RESCUE: CMD+ALT+CTRL+0, unhides all windows
-- =============================================================================
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "0", function()
    hs.alert.show("🚨 Emergency Rescue Initiated 🚨")
    local wins = hs.window.allWindows()
    local screen = hs.screen.mainScreen():frame()
    for _, win in ipairs(wins) do
        -- Force show
        win:setFrame({
            x = screen.x + 50,
            y = screen.y + 50,
            w = screen.w - 100,
            h = screen.h - 100,
        })
        win:raise()
    end
end)

require("macos-vim-navigation/init")

local clock = hs.loadSpoon("AClock")

local VimMode = hs.loadSpoon("VimMode")
local vim = VimMode:new()
vim:bindHotKeys({ enter = { { "alt" }, "e" } })

-- =============================================================================
-- BASE SETTINGS
-- =============================================================================
hs.window.animationDuration = 0
hs.ipc.cliInstall()

-- =============================================================================
-- NANOWM v39
-- =============================================================================
NanoWM = {}

-- -----------------------------------------------------------------------------
-- PERSISTENCE
-- -----------------------------------------------------------------------------
function NanoWM.loadState()
    local function clean(t)
        local out = {}
        for k, v in pairs(t or {}) do
            out[tonumber(k) or k] = v
        end
        return out
    end
    NanoWM.tags = clean(hs.settings.get("nanoWM_tags"))
    NanoWM.stacks = clean(hs.settings.get("nanoWM_stacks"))
    NanoWM.sticky = clean(hs.settings.get("nanoWM_sticky"))
    NanoWM.floatingOverrides = clean(hs.settings.get("nanoWM_floatingOverrides"))
    NanoWM.floatingCache = hs.settings.get("nanoWM_floatingCache") or {}
    NanoWM.sizeCache = hs.settings.get("nanoWM_sizeCache") or {}
    NanoWM.fullscreenCache = hs.settings.get("nanoWM_fullscreenCache") or {}
    NanoWM.masterWidths = clean(hs.settings.get("nanoWM_masterWidths")) or {}
    NanoWM.appTagMemory = hs.settings.get("nanoWM_appTagMemory") or {}
    NanoWM.freeTags = clean(hs.settings.get("nanoWM_freeTags")) or {}
end

NanoWM.saveTimer = hs.timer.delayed.new(2.0, function()
    local function serialize(t)
        local out = {}
        for k, v in pairs(t or {}) do
            out[tostring(k)] = v
        end
        return out
    end
    hs.settings.set("nanoWM_tags", serialize(NanoWM.tags))
    hs.settings.set("nanoWM_stacks", serialize(NanoWM.stacks))
    hs.settings.set("nanoWM_sticky", serialize(NanoWM.sticky))
    hs.settings.set("nanoWM_floatingOverrides", serialize(NanoWM.floatingOverrides))

    hs.settings.set("nanoWM_floatingCache", NanoWM.floatingCache)
    hs.settings.set("nanoWM_sizeCache", NanoWM.sizeCache)
    hs.settings.set("nanoWM_fullscreenCache", NanoWM.fullscreenCache)
    hs.settings.set("nanoWM_masterWidths", serialize(NanoWM.masterWidths))

    hs.settings.set("nanoWM_currentTag", NanoWM.currentTag)
    hs.settings.set("nanoWM_prevTag", NanoWM.prevTag)
    hs.settings.set("nanoWM_appTagMemory", NanoWM.appTagMemory)
    hs.settings.set("nanoWM_sketchybarEnabled", NanoWM.sketchybarEnabled)
    hs.settings.set("nanoWM_bordersEnabled", NanoWM.bordersEnabled)
    hs.settings.set("nanoWM_freeTags", serialize(NanoWM.freeTags))
end)

function NanoWM.triggerSave()
    NanoWM.saveTimer:start()
end

-- Initialize State
NanoWM.tags = {}
NanoWM.stacks = {}
NanoWM.sticky = {}
NanoWM.floatingOverrides = {}
NanoWM.floatingCache = {}
NanoWM.sizeCache = {}
NanoWM.fullscreenCache = {}
NanoWM.windowState = {}
NanoWM.appTagMemory = {}
NanoWM.freeTags = {}         -- Tags in "free mode" (no tiling)
NanoWM.freeTagPositions = {} -- Cache window positions before entering free mode

-- Pending destruction: delay tag cleanup to handle false positives
NanoWM.pendingDestruction = {} -- { [id] = { tag = X, appName = Y, timer = Z } }
NanoWM.destructionDelay = 0.5  -- seconds to wait before actually clearing tag

NanoWM.loadState()

NanoWM.currentTag = hs.settings.get("nanoWM_currentTag") or 1
NanoWM.prevTag = hs.settings.get("nanoWM_prevTag") or 1
NanoWM.masterWidths = {}
NanoWM.defaultMasterWidth = 0.5
NanoWM.gap = 0
NanoWM.layout = "tile"
NanoWM.isFullscreen = false
NanoWM.special = { active = false, tag = "special", border = nil, raiseTimer = nil }
NanoWM.actionsCache = {}

-- GUARDS
NanoWM.focusTimer = nil
NanoWM.launching = false
NanoWM.tileTimer = nil

-- Timer tracking
NanoWM.activeTimer = nil
NanoWM.timerEndTime = nil
NanoWM.timerDuration = nil

-- Urgent tags (Awesome WM style)
NanoWM.urgentTags = {}         -- Table of urgent tags: { [tag] = true }
NanoWM.lastManualTagSwitch = 0 -- Timestamp of last manual tag switch
NanoWM.tagSwitchCooldown = 1.0 -- Increased cooldown

-- Anti-jump protection - track when we're in a "safe" state
NanoWM.lastTileTime = 0
NanoWM.tileProtectionWindow = 0.5 -- Don't process focus events within 0.5s of tiling   -- Cooldown in seconds after manual switch

-- Apps that should trigger urgent (browsers, communication apps)
NanoWM.urgentApps = {
    ["Firefox"] = true,
    ["Safari"] = true,
    ["Google Chrome"] = true,
    ["Slack"] = true,
    ["Discord"] = true,
    ["Messages"] = true,
    ["Telegram"] = true,
    ["WhatsApp"] = true,
    ["Microsoft Teams"] = true,
    ["Zoom"] = true,
}

-- Apps that should remember their tag by title (multi-window apps)
-- Apps excluded from tag memory (these apps will NOT have their tags remembered)
NanoWM.excludedFromTagMemory = {
    ["Alacritty"] = true,
    ["Terminal"] = true,
    ["iTerm2"] = true,
    ["Finder"] = true,
    ["System Settings"] = true,
}

-- -----------------------------------------------------------------------------
-- CONFIGURATION
-- -----------------------------------------------------------------------------
NanoWM.floatingApps = {
    ["System Settings"] = true,
    ["Activity Monitor"] = true,
    ["Calculator"] = true,
    ["Raycast"] = true,
    ["Finder"] = true,
    ["Photo Booth"] = true,
    ["Archive Utility"] = true,
    ["App Store"] = true,
    ["Marta"] = true,
    ["Hammerspoon"] = true,
    ["Disk Utility"] = true,
    ["Dock"] = true,
    ["Control Center"] = true,
    ["Notification Center"] = true,
    ["Spotlight"] = true,
    ["SecurityAgent"] = true,
    ["CoreAuthUI"] = true,
    ["loginwindow"] = true,
    ["Force Quit Applications"] = true,
}

NanoWM.floatingTitles = {
    "ORGINDEX",
    "Picture-in-Picture",
    "Copy",
    "Move",
    "Info",
    "Task Switcher",
}

-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- WINDOW TAG PERSISTENCE (by app name + title pattern)
-- -----------------------------------------------------------------------------
function NanoWM.getWindowKey(win)
    if not win then
        return nil
    end
    local app = win:application()
    if not app then
        return nil
    end
    local appName = app:name()
    local title = win:title() or ""

    if NanoWM.excludedFromTagMemory[appName] then
        return nil
    end

    -- Skip generic/empty titles
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

    -- Use first 60 chars of normalized title
    local shortTitle = string.sub(normalizedTitle, 1, 60)
    return appName .. "::" .. shortTitle
end

function NanoWM.rememberWindowTag(win, tag)
    local key = NanoWM.getWindowKey(win)
    if key then
        NanoWM.appTagMemory[key] = tag
        NanoWM.triggerSave()
    end
end

function NanoWM.getRememberedTag(win)
    local key = NanoWM.getWindowKey(win)
    if key and NanoWM.appTagMemory[key] then
        return NanoWM.appTagMemory[key]
    end
    return nil
end

function NanoWM.saveCurrentWindowTag()
    local win = hs.window.focusedWindow()
    if not win then
        hs.alert.show("No focused window")
        return
    end

    local app = win:application()
    if not app then
        hs.alert.show("Cannot get app")
        return
    end

    local appName = app:name()
    if NanoWM.excludedFromTagMemory[appName] then
        hs.alert.show(appName .. " is excluded from tag memory")
        return
    end

    local key = NanoWM.getWindowKey(win)
    if not key then
        hs.alert.show("Window has no valid title to save")
        return
    end

    local tag = NanoWM.tags[win:id()]
    if not tag then
        hs.alert.show("Window has no tag")
        return
    end

    NanoWM.appTagMemory[key] = tag
    NanoWM.triggerSave()
    hs.alert.show("Saved: " .. string.sub(key, 1, 30) .. "... -> Tag " .. tostring(tag))
end

function NanoWM.saveAllWindowTags()
    local saved = 0
    local skipped = 0
    for _, win in ipairs(hs.window.filter.default:getWindows()) do
        local app = win:application()
        if app then
            local appName = app:name()
            if not NanoWM.excludedFromTagMemory[appName] then
                local key = NanoWM.getWindowKey(win)
                if key then
                    local tag = NanoWM.tags[win:id()]
                    if tag then
                        NanoWM.appTagMemory[key] = tag
                        saved = saved + 1
                    end
                else
                    skipped = skipped + 1
                end
            else
                skipped = skipped + 1
            end
        end
    end
    NanoWM.triggerSave()
    hs.alert.show("Saved " .. saved .. " window tags (skipped " .. skipped .. ")")
end

-- URGENT TAG FUNCTIONS
-- -----------------------------------------------------------------------------
function NanoWM.markTagUrgent(tag)
    if tag == NanoWM.currentTag then
        return
    end
    if tag == NanoWM.special.tag and NanoWM.special.active then
        return
    end

    if not NanoWM.urgentTags[tag] then
        NanoWM.urgentTags[tag] = true
        NanoWM.updateSketchybar()
    end
end

function NanoWM.clearUrgent(tag)
    if NanoWM.urgentTags[tag] then
        NanoWM.urgentTags[tag] = nil
        NanoWM.updateSketchybar()
    end
end

function NanoWM.gotoUrgent()
    for tag, _ in pairs(NanoWM.urgentTags) do
        if tag == "special" then
            NanoWM.toggleSpecial()
        else
            NanoWM.gotoTag(tag)
        end
        return
    end
    hs.alert.show("No urgent tags")
end

function NanoWM.hasUrgentTags()
    for _, _ in pairs(NanoWM.urgentTags) do
        return true
    end
    return false
end

-- -----------------------------------------------------------------------------
-- FREE MODE FUNCTIONS (disable tiling on a tag)
-- -----------------------------------------------------------------------------
function NanoWM.isTagFree(tag)
    tag = tag or (NanoWM.special.active and NanoWM.special.tag or NanoWM.currentTag)
    return NanoWM.freeTags[tag] == true
end

function NanoWM.toggleFreeMode()
    local tag = NanoWM.special.active and NanoWM.special.tag or NanoWM.currentTag

    if NanoWM.freeTags[tag] then
        -- Exiting free mode - re-tile windows
        NanoWM.freeTags[tag] = nil
        NanoWM.freeTagPositions[tag] = nil
        hs.alert.show("Free Mode: OFF (Tag " .. tostring(tag) .. ")")
        NanoWM.tile()
    else
        -- Entering free mode - cache current positions first
        local windows = NanoWM.getTiledWindows(tag)
        NanoWM.freeTagPositions[tag] = {}
        for _, win in ipairs(windows) do
            local id = win:id()
            local f = win:frame()
            NanoWM.freeTagPositions[tag][id] = { x = f.x, y = f.y, w = f.w, h = f.h }
        end
        NanoWM.freeTags[tag] = true
        hs.alert.show("Free Mode: ON (Tag " .. tostring(tag) .. ")")
    end

    NanoWM.triggerSave()
    NanoWM.updateSketchybar()
end

-- -----------------------------------------------------------------------------
-- PER-TAG MASTER WIDTH HELPERS
-- -----------------------------------------------------------------------------
function NanoWM.getMasterWidth(tag)
    tag = tag or NanoWM.currentTag
    return NanoWM.masterWidths[tag] or NanoWM.defaultMasterWidth
end

function NanoWM.setMasterWidth(tag, width)
    tag = tag or NanoWM.currentTag
    NanoWM.masterWidths[tag] = width
    NanoWM.triggerSave()
end

function NanoWM.resetMasterWidthIfNeeded(tag)
    tag = tag or NanoWM.currentTag
    local windows = NanoWM.getTiledWindows(tag)
    if #windows <= 1 then
        NanoWM.masterWidths[tag] = NanoWM.defaultMasterWidth
        NanoWM.triggerSave()
    end
end

-- -----------------------------------------------------------------------------
-- CORE HELPERS
-- -----------------------------------------------------------------------------
function NanoWM.isFloating(win)
    if not win then
        return false
    end
    local id = win:id()
    if NanoWM.floatingOverrides[id] ~= nil then
        return NanoWM.floatingOverrides[id]
    end
    if NanoWM.sticky[id] then
        return true
    end

    local app = win:application()
    if not app then
        return false
    end
    if NanoWM.floatingApps[app:name()] then
        return true
    end

    local title = win:title() or ""
    for _, str in ipairs(NanoWM.floatingTitles) do
        if string.find(title, str) then
            return true
        end
    end
    if title == "Picture-in-Picture" then
        return true
    end
    return win:isStandard() == false
end

function NanoWM.registerWindow(win)
    local id = win:id()
    if not NanoWM.tags[id] then
        local app = win:application()
        local appName = app and app:name() or "Unknown"

        local rememberedTag = NanoWM.getRememberedTag(win)
        local targetTag

        if rememberedTag then
            targetTag = rememberedTag
            print("[NanoWM] Window opened with remembered tag: " .. tostring(rememberedTag))
        else
            -- Check if this app recently had a window destroyed (crash recovery)
            local now = hs.timer.secondsSinceEpoch()
            local recoveryTag = nil
            for oldId, info in pairs(NanoWM.pendingDestruction) do
                if info.appName == appName and info.tag and (now - info.time) < 2.0 then
                    recoveryTag = info.tag
                    print("[NanoWM] Crash recovery: " .. appName .. " was on tag " .. tostring(recoveryTag))
                    -- Cancel the pending destruction since we're recovering
                    if info.timer then
                        info.timer:stop()
                    end
                    NanoWM.pendingDestruction[oldId] = nil
                    break
                end
            end

            if recoveryTag then
                targetTag = recoveryTag
            else
                -- Use current tag (or special if active)
                targetTag = NanoWM.special.active and NanoWM.special.tag or NanoWM.currentTag
            end
        end

        NanoWM.tags[id] = targetTag
        if not NanoWM.isFloating(win) then
            if not NanoWM.stacks[targetTag] then
                NanoWM.stacks[targetTag] = {}
            end
            local found = false
            for _, existingId in ipairs(NanoWM.stacks[targetTag]) do
                if existingId == id then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(NanoWM.stacks[targetTag], 1, id)
            end
        end

        NanoWM.triggerSave()
    end
end

function NanoWM.getTiledWindows(tag)
    local stackIds = NanoWM.stacks[tag] or {}
    local windows = {}
    local cleanStack = {}
    for _, id in ipairs(stackIds) do
        local win = hs.window.get(id)
        -- IMPORTANT: Verify the window's tag actually matches (fixes multi-tag bug)
        if win and win:isVisible() and NanoWM.tags[id] == tag then
            if not NanoWM.isFloating(win) then
                table.insert(windows, win)
                table.insert(cleanStack, id)
            end
        elseif hs.window.get(id) and NanoWM.tags[id] == tag then
            -- Window exists but not visible, keep in stack
            table.insert(cleanStack, id)
        end
        -- If tag doesn't match, don't add to cleanStack (removes stale entries)
    end
    local allWins = hs.window.filter.default:getWindows()
    for _, win in ipairs(allWins) do
        local id = win:id()
        if NanoWM.tags[id] == tag and not NanoWM.isFloating(win) then
            local inStack = false
            for _, sid in ipairs(cleanStack) do
                if sid == id then
                    inStack = true
                    break
                end
            end
            if not inStack then
                table.insert(windows, 1, win)
                table.insert(cleanStack, 1, id)
            end
        end
    end
    if #cleanStack ~= #stackIds then
        NanoWM.stacks[tag] = cleanStack
        NanoWM.triggerSave()
    end
    return windows
end

function NanoWM.getAllVisibleWindows()
    local tag = NanoWM.special.active and NanoWM.special.tag or NanoWM.currentTag
    local list = NanoWM.getTiledWindows(tag)
    for _, win in ipairs(hs.window.filter.default:getWindows()) do
        local id = win:id()
        local isSticky = NanoWM.sticky[id]
        local isFloat = NanoWM.isFloating(win)
        local onTag = (NanoWM.tags[id] == tag)
        local isPip = (win:title() == "Picture-in-Picture")
        if not isPip and ((isFloat and onTag) or isSticky) then
            local seen = false
            for _, w in ipairs(list) do
                if w:id() == id then
                    seen = true
                    break
                end
            end
            if not seen then
                table.insert(list, win)
            end
        end
    end
    return list
end

-- -----------------------------------------------------------------------------
-- LAYOUT ENGINE (Robust Z-Order)
-- -----------------------------------------------------------------------------
NanoWM.tileTimer = hs.timer.delayed.new(0.02, function()
    NanoWM.performTile()
end)

function NanoWM.tile()
    NanoWM.tileTimer:start()
end

-- Helper to force raise all visible floating windows
function NanoWM.raiseFloating()
    local tag = NanoWM.special.active and NanoWM.special.tag or NanoWM.currentTag

    -- First pass: raise floating windows (only those that SHOULD be visible)
    local floatingWins = {}
    for _, win in ipairs(hs.window.filter.default:getWindows()) do
        local id = win:id()
        local winTag = NanoWM.tags[id]
        local isSticky = NanoWM.sticky[id]
        local isPip = (win:title() == "Picture-in-Picture")
        local isFloat = NanoWM.isFloating(win)

        -- Determine if window should be visible (same logic as performTile)
        local isVisible = false
        if winTag == NanoWM.currentTag then
            isVisible = true
        end
        if NanoWM.special.active and winTag == NanoWM.special.tag then
            isVisible = true
        end
        if isSticky or isPip then
            isVisible = true
        end
        -- Floating windows not on current tag and not sticky/pip should NOT be visible
        if isFloat and not isSticky and not isPip and winTag ~= NanoWM.currentTag and winTag ~= NanoWM.special.tag then
            isVisible = false
        end

        if isVisible and isFloat then
            if win:frame().x < 90000 then -- Only if not hidden
                table.insert(floatingWins, win)
            end
        end
    end

    -- Raise floating windows
    for _, win in ipairs(floatingWins) do
        win:raise()
    end

    -- Second pass: raise special tag windows on top of everything (including floating)
    if NanoWM.special.active then
        local specialWins = NanoWM.getTiledWindows(NanoWM.special.tag)
        for _, win in ipairs(specialWins) do
            if win:frame().x < 90000 then
                win:raise()
            end
        end
    end
end

function NanoWM.performTile()
    -- Mark tile time for anti-jump protection
    NanoWM.lastTileTime = hs.timer.secondsSinceEpoch()

    local screen = hs.screen.mainScreen()
    local frame = screen:frame()

    local toHide = {}
    local toFloat = {}

    -- PHASE 1: CLASSIFICATION
    for _, win in ipairs(hs.window.filter.default:getWindows()) do
        local id = win:id()
        NanoWM.registerWindow(win)

        local winTag = NanoWM.tags[id]
        local isSticky = NanoWM.sticky[id]
        local isPip = (win:title() == "Picture-in-Picture")
        local isFloat = NanoWM.isFloating(win)

        local isVisible = false
        if winTag == NanoWM.currentTag then
            isVisible = true
        end
        if NanoWM.special.active and winTag == NanoWM.special.tag then
            isVisible = true
        end
        if isSticky or isPip then
            isVisible = true
        end

        if isFloat and not isSticky and not isPip and winTag ~= NanoWM.currentTag and winTag ~= NanoWM.special.tag then
            isVisible = false
        end

        if not NanoWM.windowState[id] then
            NanoWM.windowState[id] = { isHidden = false }
        end

        if isVisible then
            if isFloat then
                table.insert(toFloat, win)
            end
        else
            table.insert(toHide, win)
        end
    end

    -- PHASE 2: HIDE
    for _, win in ipairs(toHide) do
        local id = win:id()
        local idStr = tostring(id)

        -- Cache valid position before hiding
        if not NanoWM.windowState[id].isHidden and NanoWM.isFloating(win) then
            local f = win:frame()
            if f.x < 10000 then -- Strict check: Must be on screen
                NanoWM.floatingCache[idStr] = { x = f.x, y = f.y, w = f.w, h = f.h }
            end
        end

        -- Move to bottom-right corner (minimal visibility - just a few pixels)
        local f = win:frame()
        if f.x < 90000 then
            local screenFrame = hs.screen.mainScreen():frame()
            f.x = screenFrame.x + screenFrame.w - 5 -- Only 5 pixels visible
            f.y = screenFrame.y + screenFrame.h - 5
            win:setFrame(f)
            NanoWM.windowState[id].isHidden = true
        end
    end

    -- PHASE 3: TILE BACKGROUND (skip if tag is in free mode)
    local backgroundWindows = NanoWM.getTiledWindows(NanoWM.currentTag)
    if not NanoWM.isTagFree(NanoWM.currentTag) then
        NanoWM.applyLayout(backgroundWindows, frame, false, NanoWM.currentTag)
    else
        -- In free mode, just make sure windows are visible (not hidden)
        for _, win in ipairs(backgroundWindows) do
            local id = win:id()
            if NanoWM.windowState[id] and NanoWM.windowState[id].isHidden then
                -- Restore from cache if available
                local idStr = tostring(id)
                local cached = NanoWM.freeTagPositions[NanoWM.currentTag]
                    and NanoWM.freeTagPositions[NanoWM.currentTag][id]
                if cached then
                    win:setFrame(cached)
                else
                    win:centerOnScreen()
                end
                NanoWM.windowState[id].isHidden = false
            end
        end
    end

    if NanoWM.special.active then
        local specialWindows = NanoWM.getTiledWindows(NanoWM.special.tag)
        if not NanoWM.isTagFree(NanoWM.special.tag) then
            local pad = 100
            local specialFrame =
            { x = frame.x + pad, y = frame.y + pad, w = frame.w - (pad * 2), h = frame.h - (pad * 2) }
            NanoWM.applyLayout(specialWindows, specialFrame, true, NanoWM.special.tag)
        else
            -- In free mode for special tag, just make sure windows are visible
            for _, win in ipairs(specialWindows) do
                local id = win:id()
                if NanoWM.windowState[id] and NanoWM.windowState[id].isHidden then
                    local cached = NanoWM.freeTagPositions[NanoWM.special.tag]
                        and NanoWM.freeTagPositions[NanoWM.special.tag][id]
                    if cached then
                        win:setFrame(cached)
                    else
                        win:centerOnScreen()
                    end
                    NanoWM.windowState[id].isHidden = false
                end
            end
        end

        -- Immediately raise all special windows to ensure they're on top
        for _, win in ipairs(specialWindows) do
            win:raise()
        end
    end

    -- PHASE 4: FLOAT RESTORE
    for _, win in ipairs(toFloat) do
        local id = win:id()
        local idStr = tostring(id)

        -- If hidden, restore
        if NanoWM.windowState[id].isHidden or win:frame().x >= 90000 then
            local saved = NanoWM.floatingCache[idStr]
            if saved and saved.x < 10000 then
                win:setFrame(saved)
            else
                win:centerOnScreen()
            end
            NanoWM.windowState[id].isHidden = false
            -- Raise the window after restoring it
            win:raise()
        end
    end

    -- PHASE 5: ENSURE SPECIAL WINDOWS ON TOP
    -- Extra raise for special windows after everything is settled
    if NanoWM.special.active then
        hs.timer.doAfter(0.05, function()
            local specialWins = NanoWM.getTiledWindows(NanoWM.special.tag)
            for _, win in ipairs(specialWins) do
                if win:frame().x < 90000 then
                    win:raise()
                end
            end
        end)
    end

    NanoWM.updateSketchybar()
    NanoWM.updateBordersVisibility()
end

function NanoWM.applyLayout(windows, area, isSpecial, tag)
    local count = #windows
    if count == 0 then
        return
    end
    local gap = NanoWM.gap

    local function setFrameSmart(win, newFrame)
        local f = win:frame()
        if
            math.abs(f.x - newFrame.x) > 1
            or math.abs(f.y - newFrame.y) > 1
            or math.abs(f.w - newFrame.w) > 1
            or math.abs(f.h - newFrame.h) > 1
        then
            win:setFrame(newFrame)
        end
    end

    if NanoWM.isFullscreen and not isSpecial then
        for _, win in ipairs(windows) do
            setFrameSmart(win, hs.screen.mainScreen():frame())
        end
        return
    end

    if NanoWM.layout == "monocle" then
        for _, win in ipairs(windows) do
            setFrameSmart(win, area)
        end
        return
    end

    local masterWin = windows[1]
    if count == 1 then
        setFrameSmart(masterWin, { x = area.x + gap, y = area.y + gap, w = area.w - (2 * gap), h = area.h - (2 * gap) })
    else
        local masterWidth = NanoWM.getMasterWidth(tag)
        local mw = math.floor(area.w * masterWidth)
        setFrameSmart(masterWin, { x = area.x + gap, y = area.y + gap, w = mw - (1.5 * gap), h = area.h - (2 * gap) })
        local sx = area.x + mw + (0.5 * gap)
        local sw = area.w - mw - (1.5 * gap)
        local sh = (area.h - (gap * count)) / (count - 1)
        for i = 2, count do
            setFrameSmart(windows[i], { x = sx, y = area.y + gap + ((i - 2) * (sh + gap)), w = sw, h = sh })
        end
    end
end

-- -----------------------------------------------------------------------------
-- ACTIONS
-- -----------------------------------------------------------------------------
function NanoWM.toggleFloat()
    local win = hs.window.focusedWindow()
    if not win then
        return
    end
    local id = win:id()
    local idStr = tostring(id)
    local currentlyFloating = NanoWM.isFloating(win)

    NanoWM.floatingOverrides[id] = not currentlyFloating
    local tag = NanoWM.tags[id]

    if currentlyFloating then
        -- Float -> Tile
        local f = win:frame()
        if f.x < 10000 then
            NanoWM.sizeCache[idStr] = { w = f.w, h = f.h }
        end
        if not NanoWM.stacks[tag] then
            NanoWM.stacks[tag] = {}
        end
        table.insert(NanoWM.stacks[tag], 1, id)
    else
        -- Tile -> Float
        if NanoWM.stacks[tag] then
            for i, vid in ipairs(NanoWM.stacks[tag]) do
                if vid == id then
                    table.remove(NanoWM.stacks[tag], i)
                    break
                end
            end
        end
        -- Restore
        local saved = NanoWM.sizeCache[idStr]
        local screen = win:screen():frame()
        if saved and (math.abs(saved.w - screen.w) > 50) then
            local newX = screen.x + (screen.w - saved.w) / 2
            local newY = screen.y + (screen.h - saved.h) / 2
            win:setFrame({ x = newX, y = newY, w = saved.w, h = saved.h })
        else
            local w, h = screen.w * 0.7, screen.h * 0.7
            local x = screen.x + (screen.w - w) / 2
            local y = screen.y + (screen.h - h) / 2
            win:setFrame({ x = x, y = y, w = w, h = h })
        end
        win:raise()
    end
    NanoWM.triggerSave()
    NanoWM.tile()
    -- hs.alert.show(currentlyFloating and "Window Tiled" or "Window Floating")
end

function NanoWM.toggleSticky()
    local win = hs.window.focusedWindow()
    if not win then
        return
    end
    local id = win:id()
    if NanoWM.sticky[id] then
        NanoWM.sticky[id] = nil
        -- hs.alert.show("Window Un-Stuck")
    else
        NanoWM.sticky[id] = true
        win:raise()
        -- hs.alert.show("Window Sticky")
    end
    NanoWM.triggerSave()
    NanoWM.tile()
end

function NanoWM.toggleFullscreen()
    local win = hs.window.focusedWindow()
    if not win then
        return
    end
    local idStr = tostring(win:id())

    if NanoWM.isFloating(win) then
        if NanoWM.fullscreenCache[idStr] then -- Restore
            win:setFrame(NanoWM.fullscreenCache[idStr])
            NanoWM.fullscreenCache[idStr] = nil
        else -- Maximize
            local f = win:frame()
            NanoWM.fullscreenCache[idStr] = { x = f.x, y = f.y, w = f.w, h = f.h }
            win:setFrame(hs.screen.mainScreen():frame())
        end
        win:raise()
    else
        NanoWM.isFullscreen = not NanoWM.isFullscreen
        if NanoWM.isFullscreen then
            win:raise()
        end
        NanoWM.tile()
    end
    NanoWM.triggerSave()
end

function NanoWM.cycleFocus(dir)
    local allVisible

    -- When special tag is active, ONLY cycle through special tag windows
    if NanoWM.special.active then
        allVisible = NanoWM.getTiledWindows(NanoWM.special.tag)
        -- Add floating windows on special tag
        for _, win in ipairs(hs.window.filter.default:getWindows()) do
            local id = win:id()
            if NanoWM.tags[id] == NanoWM.special.tag and NanoWM.isFloating(win) then
                local seen = false
                for _, w in ipairs(allVisible) do
                    if w:id() == id then
                        seen = true
                        break
                    end
                end
                if not seen then
                    table.insert(allVisible, win)
                end
            end
        end
    else
        allVisible = NanoWM.getAllVisibleWindows()
    end

    if #allVisible == 0 then
        return
    end
    local focused = hs.window.focusedWindow()
    local idx = 0
    if focused then
        for i, win in ipairs(allVisible) do
            if win:id() == focused:id() then
                idx = i
                break
            end
        end
    end
    if idx == 0 then
        idx = 1
    end
    local newIdx = idx + dir
    if newIdx < 1 then
        newIdx = #allVisible
    end
    if newIdx > #allVisible then
        newIdx = 1
    end
    local targetWin = allVisible[newIdx]
    targetWin:focus()

    -- Only raise the focused window if it's floating (don't raise all floats)
    if NanoWM.isFloating(targetWin) then
        targetWin:raise()
    end
end

function NanoWM.swapWindow(dir)
    local tag = NanoWM.special.active and NanoWM.special.tag or NanoWM.currentTag
    local stack = NanoWM.stacks[tag]
    if not stack or #stack < 2 then
        return
    end
    local focused = hs.window.focusedWindow()
    if not focused then
        return
    end
    if NanoWM.isFloating(focused) then
        -- hs.alert.show("Cannot swap floating window")
        return
    end

    local fid = focused:id()
    local idx = 0
    for i, id in ipairs(stack) do
        if id == fid then
            idx = i
            break
        end
    end
    if idx == 0 then
        return
    end
    local targetIdx = idx + dir
    if targetIdx < 1 then
        targetIdx = #stack
    end
    if targetIdx > #stack then
        targetIdx = 1
    end
    stack[idx], stack[targetIdx] = stack[targetIdx], stack[idx]
    NanoWM.triggerSave()
    NanoWM.tile()
    hs.timer.doAfter(0.01, function()
        focused:focus()
    end)
end

-- -----------------------------------------------------------------------------
-- MENUS
-- -----------------------------------------------------------------------------
NanoWM.menu = hs.chooser.new(function(choice)
    if not choice then
        return
    end
    local func = NanoWM.actionsCache[choice.uuid]
    if func then
        func()
    end
end)
NanoWM.menu:width(40)
NanoWM.menu:bgDark(true)
NanoWM.menu:fgColor({ hex = "#FFFFFF" })
NanoWM.menu:subTextColor({ hex = "#CCCCCC" })

function NanoWM.openMenu(mode)
    NanoWM.actionsCache = {}
    local choices = {}
    local idx = 1

    if mode == "commands" then
        local commands = {
            { t = "Reload Config", fn = hs.reload },
            { t = "Reset Layout",  fn = NanoWM.tile },
            {
                t = "Toggle Monocle/Tile",
                fn = function()
                    NanoWM.layout = (NanoWM.layout == "tile") and "monocle" or "tile"
                    NanoWM.tile()
                end,
            },
            {
                t = "Toggle Free Mode (current tag)",
                fn = NanoWM.toggleFreeMode,
            },
            {
                t = "Show Tag Memory",
                fn = function()
                    local count = 0
                    local msg = "Tag Memory:\n"
                    for key, tag in pairs(NanoWM.appTagMemory) do
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
                    NanoWM.appTagMemory = {}
                    NanoWM.triggerSave()
                    hs.alert.show("Tag memory cleared")
                end,
            },
            {
                t = "Reset Tags",
                fn = function()
                    NanoWM.tags = {}
                    NanoWM.stacks = {}
                    NanoWM.sticky = {}
                    NanoWM.floatingOverrides = {}
                    NanoWM.appTagMemory = {}
                    NanoWM.freeTags = {}
                    NanoWM.currentTag = 1
                    NanoWM.triggerSave()
                    hs.reload()
                end,
            },
        }
        for _, cmd in ipairs(commands) do
            local idStr = tostring(idx)
            table.insert(choices, { text = cmd.t, uuid = idStr })
            NanoWM.actionsCache[idStr] = cmd.fn
            idx = idx + 1
        end
        NanoWM.menu:placeholderText("NanoWM Commands")
    elseif mode == "windows" then
        local wins = hs.window.allWindows()
        for _, win in ipairs(wins) do
            if win and win:application() and win:isVisible() then
                local appName = win:application():name() or "?"
                local winTitle = win:title() or ""
                local tag = NanoWM.tags[win:id()] or "?"
                local extra = ""
                if NanoWM.sticky[win:id()] then
                    extra = " [STICKY]"
                end
                if NanoWM.isFloating(win) then
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
                NanoWM.actionsCache[idStr] = function()
                    local t = NanoWM.tags[win:id()]
                    if t and t ~= NanoWM.currentTag then
                        if t == "special" then
                            if not NanoWM.special.active then
                                NanoWM.toggleSpecial()
                            end
                        else
                            NanoWM.gotoTag(t)
                        end
                    end
                    hs.timer.doAfter(0.1, function()
                        win:focus()
                    end)
                end
                idx = idx + 1
            end
        end
        NanoWM.menu:placeholderText("Switch Window...")
    end
    NanoWM.menu:choices(choices)
    NanoWM.menu:show()
end

NanoWM.walker = {}
NanoWM.walker.stack = {}
NanoWM.walker.chooser = hs.chooser.new(function(choice)
    if not choice then
        if #NanoWM.walker.stack > 0 then
            local parent = table.remove(NanoWM.walker.stack)
            NanoWM.walker.show(parent)
        end
        return
    end
    local item = NanoWM.actionsCache[choice.uuid]
    if item.menu then
        table.insert(NanoWM.walker.stack, NanoWM.walker.currentTable)
        NanoWM.walker.show(item.menu)
    else
        hs.application.frontmostApplication():selectMenuItem(item.title)
    end
end)
NanoWM.walker.chooser:width(40)
NanoWM.walker.chooser:bgDark(true)
NanoWM.walker.chooser:fgColor({ hex = "#FFFFFF" })
NanoWM.walker.chooser:subTextColor({ hex = "#CCCCCC" })

function NanoWM.walker.show(menuTable)
    NanoWM.walker.currentTable = menuTable
    NanoWM.actionsCache = {}
    local choices = {}
    local idx = 1
    if not menuTable then
        return
    end
    for _, item in pairs(menuTable) do
        if type(item) == "table" and item.title and #item.title > 0 then
            local idStr = tostring(idx)
            local entry = { text = item.title, uuid = idStr }
            if item.menu then
                entry.text = item.title .. " ▸"
                entry.subText = "Submenu"
            end
            table.insert(choices, entry)
            NanoWM.actionsCache[idStr] = item
            idx = idx + 1
        end
    end
    NanoWM.walker.chooser:choices(choices)
    NanoWM.walker.chooser:show()
end

function NanoWM.triggerMenuPalette()
    local app = hs.application.frontmostApplication()
    if app then
        local menuStruct = app:getMenuItems()
        if menuStruct then
            NanoWM.walker.stack = {}
            NanoWM.walker.show(menuStruct)
        else
            hs.alert.show("No menus found")
        end
    end
end

-- -----------------------------------------------------------------------------
-- STANDARD HELPERS
-- -----------------------------------------------------------------------------
function NanoWM.updateBorder()
    if NanoWM.special.active then
        if not NanoWM.special.border then
            local screen = hs.screen.mainScreen():frame()
            NanoWM.special.border = hs.canvas.new(screen)
            NanoWM.special.border:level(hs.canvas.windowLevels.overlay)
            -- Draw a thick border around the screen
            NanoWM.special.border[1] = {
                type = "rectangle",
                action = "stroke",
                strokeColor = { red = 0.2, green = 0.6, blue = 1.0, alpha = 0.8 },
                strokeWidth = 8,
                frame = { x = 4, y = 4, w = screen.w - 8, h = screen.h - 8 },
            }
        end
        NanoWM.special.border:show()
    else
        if NanoWM.special.border then
            NanoWM.special.border:hide()
        end
    end
end

function NanoWM.centerWindow()
    local win = hs.window.focusedWindow()
    if win then
        win:centerOnScreen()
    end
end

function NanoWM.launchTask(cmd, args)
    NanoWM.launching = true
    hs.task.new(cmd, nil, args):start()
    hs.timer.doAfter(2.0, function()
        NanoWM.launching = false
    end)
end

function NanoWM.gotoTag(i)
    -- Prevent tag switching when special mode is active
    -- if NanoWM.special.active then
    --     hs.alert.show("Exit special mode first (Alt+S)")
    --     return
    -- end
    if i == NanoWM.currentTag and not NanoWM.special.active then
        return
    end
    NanoWM.isFullscreen = false
    NanoWM.prevTag = NanoWM.currentTag
    NanoWM.currentTag = i
    NanoWM.special.active = false

    -- Record manual tag switch time and clear urgent for this tag
    NanoWM.lastManualTagSwitch = hs.timer.secondsSinceEpoch()
    NanoWM.clearUrgent(i)

    NanoWM.triggerSave()
    NanoWM.updateBorder()
    NanoWM.updateSketchybarNow() -- Immediate update for responsive feel
    NanoWM.tile()
    local wins = NanoWM.getTiledWindows(i)
    if #wins > 0 then
        hs.timer.doAfter(0.01, function()
            wins[1]:focus()
        end)
    end
    -- hs.alert.show("Tag " .. i, 0.4)
end

function NanoWM.togglePrevTag()
    NanoWM.gotoTag(NanoWM.prevTag)
end

function NanoWM.toggleSpecial()
    NanoWM.special.active = not NanoWM.special.active

    -- Record manual tag switch time
    NanoWM.lastManualTagSwitch = hs.timer.secondsSinceEpoch()

    -- Clear urgent for special tag when entering it
    if NanoWM.special.active then
        NanoWM.clearUrgent(NanoWM.special.tag)
    end

    NanoWM.updateBorder()
    NanoWM.tile()

    -- Stop any existing timer
    if NanoWM.special.raiseTimer then
        NanoWM.special.raiseTimer:stop()
        NanoWM.special.raiseTimer = nil
    end

    if NanoWM.special.active then
        local wins = NanoWM.getTiledWindows(NanoWM.special.tag)
        if #wins > 0 then
            -- Raise all special windows immediately (once)
            for _, win in ipairs(wins) do
                win:raise()
            end
            hs.timer.doAfter(0.01, function()
                wins[1]:focus()
            end)
        end
    else
        local wins = NanoWM.getTiledWindows(NanoWM.currentTag)
        if #wins > 0 then
            wins[1]:focus()
        end
    end
end

function NanoWM.moveWindowToTag(destTag)
    local win = hs.window.focusedWindow()
    if not win then
        return
    end
    local id = win:id()
    local currentTag = NanoWM.tags[id]
    if currentTag and NanoWM.stacks[currentTag] then
        for i, vid in ipairs(NanoWM.stacks[currentTag]) do
            if vid == id then
                table.remove(NanoWM.stacks[currentTag], i)
                break
            end
        end
    end
    NanoWM.tags[id] = destTag
    if not NanoWM.stacks[destTag] then
        NanoWM.stacks[destTag] = {}
    end
    table.insert(NanoWM.stacks[destTag], 1, id)
    -- Reset master width if only one window left on the source tag
    if currentTag then
        NanoWM.resetMasterWidthIfNeeded(currentTag)
    end

    NanoWM.triggerSave()
    NanoWM.tile()
end


-- -----------------------------------------------------------------------------
-- DOCK CLICK DETECTION
-- -----------------------------------------------------------------------------
-- Check if the mouse is currently in the Dock area
-- This helps distinguish Dock clicks from other focus events
function NanoWM.isMouseInDockArea()
    local mousePos = hs.mouse.absolutePosition()
    local screen = hs.screen.mainScreen()
    local screenFrame = screen:frame()

    -- Get Dock preferences to determine position and size
    -- Dock can be at bottom, left, or right
    local dockPos = hs.execute("defaults read com.apple.dock orientation 2>/dev/null"):gsub("%s+", "")
    if dockPos == "" then dockPos = "bottom" end

    -- Dock height/width is typically around 70-90 pixels when visible
    -- We use a generous threshold to account for different Dock sizes
    local dockThreshold = 90

    if dockPos == "bottom" then
        -- Dock at bottom: check if mouse is near the bottom of the screen
        return mousePos.y >= (screenFrame.y + screenFrame.h - dockThreshold)
    elseif dockPos == "left" then
        -- Dock at left: check if mouse is near the left edge
        return mousePos.x <= (screenFrame.x + dockThreshold)
    elseif dockPos == "right" then
        -- Dock at right: check if mouse is near the right edge
        return mousePos.x >= (screenFrame.x + screenFrame.w - dockThreshold)
    end

    return false
end

-- -----------------------------------------------------------------------------
-- WATCHERS
-- -----------------------------------------------------------------------------
local filter = hs.window.filter.new(nil)
filter:subscribe(hs.window.filter.windowCreated, function(win)
    if not win then
        return
    end
    NanoWM.registerWindow(win)
    NanoWM.tile()
end)

filter:subscribe(hs.window.filter.windowDestroyed, function(win)
    if win then
        local id = win:id()
        if not id then
            return
        end

        local idStr = tostring(id)
        local tag = NanoWM.tags[id]
        local app = win:application()
        local appName = app and app:name() or "Unknown"

        -- Cancel any existing pending destruction for this window
        if NanoWM.pendingDestruction[id] and NanoWM.pendingDestruction[id].timer then
            NanoWM.pendingDestruction[id].timer:stop()
        end

        -- Store the window's tag for potential recovery
        NanoWM.pendingDestruction[id] = {
            tag = tag,
            appName = appName,
            time = hs.timer.secondsSinceEpoch(),
        }

        -- Delay the actual cleanup
        NanoWM.pendingDestruction[id].timer = hs.timer.doAfter(NanoWM.destructionDelay, function()
            -- Check if window still doesn't exist (wasn't a false positive)
            local stillExists = hs.window.get(id)
            if stillExists then
                print("[NanoWM] Window " .. tostring(id) .. " reappeared, not cleaning up")
                NanoWM.pendingDestruction[id] = nil
                return
            end

            print(
                "[NanoWM] Cleaning up destroyed window: "
                .. appName
                .. " (id: "
                .. tostring(id)
                .. ") was on tag "
                .. tostring(tag)
            )

            -- Now actually clean up - remove from ALL stacks (not just the tagged one)
            -- This handles edge cases where window might be in wrong stack
            for stackTag, stack in pairs(NanoWM.stacks) do
                for i = #stack, 1, -1 do  -- Iterate backwards for safe removal
                    if stack[i] == id then
                        table.remove(stack, i)
                    end
                end
            end
            NanoWM.tags[id] = nil
            NanoWM.sticky[id] = nil
            NanoWM.floatingOverrides[id] = nil
            NanoWM.windowState[id] = nil

            if NanoWM.floatingCache then
                NanoWM.floatingCache[idStr] = nil
            end
            if NanoWM.fullscreenCache then
                NanoWM.fullscreenCache[idStr] = nil
            end
            if NanoWM.sizeCache then
                NanoWM.sizeCache[idStr] = nil
            end

            -- Reset master width if only one window left on the tag
            if tag then
                NanoWM.resetMasterWidthIfNeeded(tag)
            end

            NanoWM.pendingDestruction[id] = nil
            NanoWM.triggerSave()
            NanoWM.tile()
        end)
    end

    -- Don't immediately focus another window or tile - wait for the delay
end)

filter:subscribe(hs.window.filter.windowFocused, function(win)
    if not win then
        return
    end
    if NanoWM.launching then
        return
    end

    -- Anti-jump protection - ignore focus events right after tiling
    local timeSinceTile = hs.timer.secondsSinceEpoch() - NanoWM.lastTileTime
    if timeSinceTile < NanoWM.tileProtectionWindow then
        return
    end
    -- Check cooldown from manual tag switch
    local timeSinceSwitch = hs.timer.secondsSinceEpoch() - NanoWM.lastManualTagSwitch
    if timeSinceSwitch < NanoWM.tagSwitchCooldown then
        return
    end

    if NanoWM.isFloating(win) then
        win:raise()
        return
    end

    local id = win:id()
    local tag = NanoWM.tags[id]

    -- If window is on current tag or special tag, nothing to do
    if not tag or tag == NanoWM.currentTag or tag == "special" then
        return
    end

    -- If special mode is active and window is on special tag, nothing to do
    if NanoWM.special.active and tag == NanoWM.special.tag then
        return
    end

    -- Check if this focus was triggered by a Dock click
    local isDockClick = NanoWM.isMouseInDockArea()

    if isDockClick then
        -- Dock click: switch to the window's tag immediately
        print("[NanoWM] Dock click detected, switching to tag " .. tostring(tag))
        if tag == "special" then
            if not NanoWM.special.active then
                NanoWM.toggleSpecial()
            end
        else
            NanoWM.gotoTag(tag)
        end
        -- Focus the window after switching
        hs.timer.doAfter(0.05, function()
            win:focus()
        end)
    else
        -- Other focus event (e.g., link click): mark as urgent but don't switch
        NanoWM.markTagUrgent(tag)
    end

    -- Cancel any pending focus timer
    if NanoWM.focusTimer then
        NanoWM.focusTimer:stop()
        NanoWM.focusTimer = nil
    end
end)

-- -----------------------------------------------------------------------------
-- NEW FEATURES
-- -----------------------------------------------------------------------------

-- Gap toggle
function NanoWM.toggleGaps()
    NanoWM.gap = (NanoWM.gap == 0) and 6 or 0
    NanoWM.tile()
    hs.alert.show("Gaps: " .. (NanoWM.gap == 0 and "OFF" or "ON"))
end

-- Resize floating window to 60% and center
function NanoWM.resizeFloatingTo60()
    local win = hs.window.focusedWindow()
    if not win or not NanoWM.isFloating(win) then
        hs.alert.show("Not a floating window")
        return
    end
    local screen = win:screen():frame()
    local newW = screen.w * 0.6
    local newH = screen.h * 0.6
    local newX = screen.x + (screen.w - newW) / 2
    local newY = screen.y + (screen.h - newH) / 2
    win:setFrame({ x = newX, y = newY, w = newW, h = newH })
end

-- Resize floating window (increase/decrease by 5%)
function NanoWM.resizeFloatingWindow(direction)
    local win = hs.window.focusedWindow()
    if not win or not NanoWM.isFloating(win) then
        hs.alert.show("Not a floating window")
        return
    end
    local frame = win:frame()
    local screen = win:screen():frame()
    local delta = 0.05

    if direction == "wider" then
        frame.w = math.min(frame.w * (1 + delta), screen.w)
        frame.x = frame.x - (frame.w * delta) / 2
    elseif direction == "narrower" then
        frame.w = math.max(frame.w * (1 - delta), 200)
        frame.x = frame.x + (frame.w * delta) / 2
    elseif direction == "taller" then
        frame.h = math.min(frame.h * (1 + delta), screen.h)
        frame.y = frame.y - (frame.h * delta) / 2
    elseif direction == "shorter" then
        frame.h = math.max(frame.h * (1 - delta), 200)
        frame.y = frame.y + (frame.h * delta) / 2
    end

    win:setFrame(frame)
end

-- Move floating window
function NanoWM.moveFloatingWindow(direction)
    local win = hs.window.focusedWindow()
    if not win or not NanoWM.isFloating(win) then
        hs.alert.show("Not a floating window")
        return
    end
    local frame = win:frame()
    local screen = win:screen():frame()
    local step = 50

    if direction == "left" then
        frame.x = math.max(frame.x - step, screen.x)
    elseif direction == "right" then
        frame.x = math.min(frame.x + step, screen.x + screen.w - frame.w)
    elseif direction == "up" then
        frame.y = math.max(frame.y - step, screen.y)
    elseif direction == "down" then
        frame.y = math.min(frame.y + step, screen.y + screen.h - frame.h)
    end

    win:setFrame(frame)
end

-- Timer functions
NanoWM.activeTimer = nil

function NanoWM.startTimer(minutes)
    if NanoWM.activeTimer then
        NanoWM.activeTimer:stop()
    end

    NanoWM.timerDuration = minutes
    NanoWM.timerEndTime = os.time() + (minutes * 60)

    hs.alert.show("Timer started: " .. minutes .. " min")

    NanoWM.activeTimer = hs.timer.doAfter(minutes * 60, function()
        hs.alert.show("⏰ Timer finished! (" .. minutes .. " min)", 5)
        hs.sound.getByName("Glass"):play()
        NanoWM.activeTimer = nil
        NanoWM.timerEndTime = nil
        NanoWM.timerDuration = nil

        NanoWM.updateSketchybar()
        -- Stop the 1-second update timer
        if NanoWM.sketchybarTimer then
            NanoWM.sketchybarTimer:stop()
        end
    end)

    NanoWM.updateSketchybar()
    -- Start the 1-second update timer for sketchybar countdown display
    if NanoWM.sketchybarTimer then
        NanoWM.sketchybarTimer:start()
    end
end

function NanoWM.showTimerRemaining()
    if not NanoWM.timerEndTime then
        hs.alert.show("No active timer")
        return
    end

    local remaining = NanoWM.timerEndTime - os.time()
    if remaining <= 0 then
        hs.alert.show("Timer finished!")
        return
    end

    local mins = math.floor(remaining / 60)
    local secs = remaining % 60
    hs.alert.show(string.format("⏱ Timer: %d:%02d remaining", mins, secs), 2)
end

function NanoWM.cancelTimer()
    if NanoWM.activeTimer then
        NanoWM.activeTimer:stop()
        NanoWM.activeTimer = nil
        NanoWM.timerEndTime = nil
        NanoWM.timerDuration = nil

        hs.alert.show("Timer cancelled")
        NanoWM.updateSketchybar()
        -- Stop the 1-second update timer
        if NanoWM.sketchybarTimer then
            NanoWM.sketchybarTimer:stop()
        end
    else
        hs.alert.show("No active timer")
    end
end

function NanoWM.startCustomTimer()
    local button, minutes = hs.dialog.textPrompt("Start Timer", "Enter minutes:", "", "Start", "Cancel")
    if button == "Start" then
        local min = tonumber(minutes)
        if min and min > 0 then
            NanoWM.startTimer(min)
        else
            hs.alert.show("Invalid number")
        end
    end
end

-- Keybind menu
function NanoWM.showKeybindMenu()
    NanoWM.actionsCache = {}
    local keybinds = {
        {
            category = "Navigation",
            binds = {
                {
                    key = "Alt+J",
                    desc = "Focus next window",
                    fn = function()
                        NanoWM.cycleFocus(1)
                    end,
                },
                {
                    key = "Alt+K",
                    desc = "Focus previous window",
                    fn = function()
                        NanoWM.cycleFocus(-1)
                    end,
                },
                {
                    key = "Alt+H",
                    desc = "Decrease master width",
                    fn = function()
                        local tag = NanoWM.special.active and NanoWM.special.tag or NanoWM.currentTag
                        NanoWM.setMasterWidth(tag, math.max(0.1, NanoWM.getMasterWidth(tag) - 0.05))
                        NanoWM.tile()
                    end,
                },
                {
                    key = "Alt+L",
                    desc = "Increase master width",
                    fn = function()
                        local tag = NanoWM.special.active and NanoWM.special.tag or NanoWM.currentTag
                        NanoWM.setMasterWidth(tag, math.min(0.9, NanoWM.getMasterWidth(tag) + 0.05))
                        NanoWM.tile()
                    end,
                },
            },
        },
        {
            category = "Window Management",
            binds = {
                {
                    key = "Alt+Shift+J",
                    desc = "Swap window down",
                    fn = function()
                        NanoWM.swapWindow(1)
                    end,
                },
                {
                    key = "Alt+Shift+K",
                    desc = "Swap window up",
                    fn = function()
                        NanoWM.swapWindow(-1)
                    end,
                },
                { key = "Alt+F",            desc = "Toggle fullscreen",      fn = NanoWM.toggleFullscreen },
                { key = "Alt+C",            desc = "Center window",          fn = NanoWM.centerWindow },
                { key = "Alt+Shift+C",      desc = "Resize floating to 60%", fn = NanoWM.resizeFloatingTo60 },
                { key = "Alt+Shift+Space",  desc = "Toggle float",           fn = NanoWM.toggleFloat },
                { key = "Ctrl+Alt+Shift+S", desc = "Toggle sticky",          fn = NanoWM.toggleSticky },
                {
                    key = "Alt+Shift+Q",
                    desc = "Close window",
                    fn = function()
                        local w = hs.window.focusedWindow()
                        if w then
                            w:close()
                        end
                    end,
                },
            },
        },
        {
            category = "Floating Window Resize",
            binds = {
                {
                    key = "Alt+Shift+H",
                    desc = "Make narrower",
                    fn = function()
                        NanoWM.resizeFloatingWindow("narrower")
                    end,
                },
                {
                    key = "Alt+Shift+L",
                    desc = "Make wider",
                    fn = function()
                        NanoWM.resizeFloatingWindow("wider")
                    end,
                },
                {
                    key = "Alt+Shift+K",
                    desc = "Make shorter",
                    fn = function()
                        NanoWM.resizeFloatingWindow("shorter")
                    end,
                },
                {
                    key = "Alt+Shift+J",
                    desc = "Make taller",
                    fn = function()
                        NanoWM.resizeFloatingWindow("taller")
                    end,
                },
            },
        },
        {
            category = "Floating Window Move",
            binds = {
                {
                    key = "Ctrl+Alt+H",
                    desc = "Move left",
                    fn = function()
                        NanoWM.moveFloatingWindow("left")
                    end,
                },
                {
                    key = "Ctrl+Alt+L",
                    desc = "Move right",
                    fn = function()
                        NanoWM.moveFloatingWindow("right")
                    end,
                },
                {
                    key = "Ctrl+Alt+K",
                    desc = "Move up",
                    fn = function()
                        NanoWM.moveFloatingWindow("up")
                    end,
                },
                {
                    key = "Ctrl+Alt+J",
                    desc = "Move down",
                    fn = function()
                        NanoWM.moveFloatingWindow("down")
                    end,
                },
            },
        },
        {
            category = "Tags",
            binds = {
                {
                    key = "Alt+1",
                    desc = "Go to tag 1",
                    fn = function()
                        NanoWM.gotoTag(1)
                    end,
                },
                {
                    key = "Alt+2",
                    desc = "Go to tag 2",
                    fn = function()
                        NanoWM.gotoTag(2)
                    end,
                },
                {
                    key = "Alt+3",
                    desc = "Go to tag 3",
                    fn = function()
                        NanoWM.gotoTag(3)
                    end,
                },
                {
                    key = "Alt+4",
                    desc = "Go to tag 4",
                    fn = function()
                        NanoWM.gotoTag(4)
                    end,
                },
                {
                    key = "Alt+5",
                    desc = "Go to tag 5",
                    fn = function()
                        NanoWM.gotoTag(5)
                    end,
                },
                {
                    key = "Alt+6",
                    desc = "Go to tag 6",
                    fn = function()
                        NanoWM.gotoTag(6)
                    end,
                },
                {
                    key = "Alt+7",
                    desc = "Go to tag 7",
                    fn = function()
                        NanoWM.gotoTag(7)
                    end,
                },
                {
                    key = "Alt+8",
                    desc = "Go to tag 8",
                    fn = function()
                        NanoWM.gotoTag(8)
                    end,
                },
                {
                    key = "Alt+9",
                    desc = "Go to tag 9",
                    fn = function()
                        NanoWM.gotoTag(9)
                    end,
                },
                {
                    key = "Alt+0",
                    desc = "Go to tag 10",
                    fn = function()
                        NanoWM.gotoTag(10)
                    end,
                },
                {
                    key = "Alt+Shift+1",
                    desc = "Move window to tag 1",
                    fn = function()
                        NanoWM.moveWindowToTag(1)
                    end,
                },
                {
                    key = "Alt+Shift+2",
                    desc = "Move window to tag 2",
                    fn = function()
                        NanoWM.moveWindowToTag(2)
                    end,
                },
                {
                    key = "Alt+Shift+3",
                    desc = "Move window to tag 3",
                    fn = function()
                        NanoWM.moveWindowToTag(3)
                    end,
                },
                {
                    key = "Alt+Shift+4",
                    desc = "Move window to tag 4",
                    fn = function()
                        NanoWM.moveWindowToTag(4)
                    end,
                },
                {
                    key = "Alt+Shift+5",
                    desc = "Move window to tag 5",
                    fn = function()
                        NanoWM.moveWindowToTag(5)
                    end,
                },
                { key = "Alt+Escape", desc = "Toggle previous tag", fn = NanoWM.togglePrevTag },
                { key = "Alt+S",      desc = "Toggle special tag",  fn = NanoWM.toggleSpecial },
                {
                    key = "Alt+Shift+S",
                    desc = "Move to special tag",
                    fn = function()
                        NanoWM.moveWindowToTag(NanoWM.special.tag)
                        hs.alert.show("Moved to Special")
                    end,
                },
                { key = "Alt+U",            desc = "Go to urgent tag",               fn = NanoWM.gotoUrgent },
                { key = "Alt+Shift+M",      desc = "Save window tag to memory",      fn = NanoWM.saveCurrentWindowTag },
                { key = "Ctrl+Alt+Shift+M", desc = "Save ALL window tags to memory", fn = NanoWM.saveAllWindowTags },
            },
        },
        {
            category = "Layout & Display",
            binds = {
                {
                    key = "Cmd+Space",
                    desc = "Toggle layout (tile/monocle)",
                    fn = function()
                        NanoWM.layout = (NanoWM.layout == "tile") and "monocle" or "tile"
                        NanoWM.tile()
                    end,
                },
                { key = "Alt+G",      desc = "Toggle gaps",                   fn = NanoWM.toggleGaps },
                {
                    key = "Alt+Shift+G",
                    desc = "Toggle sketchybar",
                    fn = NanoWM.toggleSketchybar,
                },
                { key = "Ctrl+Alt+B", desc = "Toggle window borders (smart)", fn = NanoWM.toggleBorders },
                {
                    key = "Ctrl+Alt+P",
                    desc = "Toggle battery saver mode",
                    fn = NanoWM.toggleBatterySaver,
                },
                { key = "Ctrl+Alt+F", desc = "Toggle free mode (disable tiling on tag)", fn = NanoWM.toggleFreeMode },
            },
        },
        {
            category = "Menus",
            binds = {
                { key = "Alt+M", desc = "App menu palette",  fn = NanoWM.triggerMenuPalette },
                {
                    key = "Alt+P",
                    desc = "Commands menu",
                    fn = function()
                        NanoWM.openMenu("commands")
                    end,
                },
                {
                    key = "Alt+I",
                    desc = "Windows menu",
                    fn = function()
                        NanoWM.openMenu("windows")
                    end,
                },
                { key = "Alt+/", desc = "This keybind menu", fn = NanoWM.showKeybindMenu },
            },
        },
        {
            category = "Applications",
            binds = {
                {
                    key = "Alt+Return",
                    desc = "New Alacritty",
                    fn = function()
                        NanoWM.launchTask("/usr/bin/open", { "-n", "-a", "Alacritty" })
                    end,
                },
                {
                    key = "Alt+Shift+Return",
                    desc = "Focus Alacritty",
                    fn = function()
                        hs.application.launchOrFocus("Alacritty")
                    end,
                },
                {
                    key = "Alt+B",
                    desc = "New Firefox",
                    fn = function()
                        NanoWM.launchTask("/usr/bin/open", { "-n", "-a", "Firefox" })
                    end,
                },
                {
                    key = "Alt+Shift+B",
                    desc = "Focus Firefox",
                    fn = function()
                        hs.application.launchOrFocus("Firefox")
                    end,
                },
                {
                    key = "Alt+D",
                    desc = "Launch Raycast",
                    fn = function()
                        hs.application.launchOrFocus("Raycast")
                    end,
                },
            },
        },
        {
            category = "Timers",
            binds = {
                {
                    key = "Alt+T, 1",
                    desc = "5 min timer",
                    fn = function()
                        NanoWM.startTimer(5)
                    end,
                },
                {
                    key = "Alt+T, 2",
                    desc = "10 min timer",
                    fn = function()
                        NanoWM.startTimer(10)
                    end,
                },
                {
                    key = "Alt+T, 3",
                    desc = "60 min timer",
                    fn = function()
                        NanoWM.startTimer(60)
                    end,
                },
                {
                    key = "Alt+T, 4",
                    desc = "120 min timer",
                    fn = function()
                        NanoWM.startTimer(120)
                    end,
                },
                { key = "Alt+T, N", desc = "Custom timer",         fn = NanoWM.startCustomTimer },
                { key = "Alt+T, R", desc = "Show timer remaining", fn = NanoWM.showTimerRemaining },
                { key = "Alt+T, C", desc = "Cancel timer",         fn = NanoWM.cancelTimer },
            },
        },
        {
            category = "System",
            binds = {
                { key = "Ctrl+Alt+Shift+R", desc = "Reload config", fn = hs.reload },
                { key = "Ctrl+Alt+Shift+C", desc = "Toggle HS console", fn = hs.toggleConsole },
                { key = "Alt+E", desc = "Enter Vim mode", fn = nil }, -- Can't trigger modal from here
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
                NanoWM.actionsCache[idStr] = bind.fn
            end
            idx = idx + 1
        end
    end

    local chooser = hs.chooser.new(function(choice)
        if not choice then
            return
        end
        local func = NanoWM.actionsCache[choice.uuid]
        if func then
            func()
        end
    end)
    chooser:width(50)
    chooser:bgDark(true)
    chooser:fgColor({ hex = "#FFFFFF" })
    chooser:subTextColor({ hex = "#CCCCCC" })
    chooser:choices(choices)
    chooser:placeholderText("Search keybinds (press Enter to execute)...")
    -- Enable searching in both text and subText
    chooser:searchSubText(true)
    chooser:show()
end

-- =============================================================================
-- KEY BINDINGS
-- =============================================================================
local alt = { "alt" }
local altShift = { "alt", "shift" }
local ctrlAlt = { "ctrl", "alt" }
local ctrlAltShift = { "ctrl", "alt", "shift" }

hs.hotkey.bind(alt, "m", function()
    NanoWM.triggerMenuPalette()
end)
hs.hotkey.bind(alt, "p", function()
    NanoWM.openMenu("commands")
end)
hs.hotkey.bind(alt, "i", function()
    NanoWM.openMenu("windows")
end)
hs.hotkey.bind(altShift, "/", function()
    hs.eventtap.keyStroke({ "cmd", "shift" }, "/")
end)

hs.hotkey.bind(alt, "j", function()
    NanoWM.cycleFocus(1)
end)
hs.hotkey.bind(alt, "k", function()
    NanoWM.cycleFocus(-1)
end)
hs.hotkey.bind(alt, "h", function()
    local tag = NanoWM.special.active and NanoWM.special.tag or NanoWM.currentTag
    local currentWidth = NanoWM.getMasterWidth(tag)
    NanoWM.setMasterWidth(tag, math.max(0.1, currentWidth - 0.05))
    NanoWM.tile()
end)
hs.hotkey.bind(alt, "l", function()
    local tag = NanoWM.special.active and NanoWM.special.tag or NanoWM.currentTag
    local currentWidth = NanoWM.getMasterWidth(tag)
    NanoWM.setMasterWidth(tag, math.min(0.9, currentWidth + 0.05))
    NanoWM.tile()
end)

for i = 1, 9 do
    hs.hotkey.bind(alt, tostring(i), function()
        NanoWM.gotoTag(i)
    end)
    hs.hotkey.bind(altShift, tostring(i), function()
        NanoWM.moveWindowToTag(i)
    end)
end
hs.hotkey.bind(alt, "0", function()
    NanoWM.gotoTag(10)
end)
hs.hotkey.bind(altShift, "0", function()
    NanoWM.moveWindowToTag(10)
end)

hs.hotkey.bind(alt, "escape", function()
    NanoWM.togglePrevTag()
end)
hs.hotkey.bind(alt, "s", function()
    NanoWM.toggleSpecial()
end)
hs.hotkey.bind(altShift, "s", function()
    NanoWM.moveWindowToTag(NanoWM.special.tag)
    hs.alert.show("Moved to Special")
end)
hs.hotkey.bind({ "cmd" }, "space", function()
    NanoWM.layout = (NanoWM.layout == "tile") and "monocle" or "tile"
    NanoWM.tile()
end)
hs.hotkey.bind(alt, "f", function()
    NanoWM.toggleFullscreen()
end)
hs.hotkey.bind(alt, "c", function()
    NanoWM.centerWindow()
end)
hs.hotkey.bind(altShift, "c", function()
    NanoWM.resizeFloatingTo60()
end)
hs.hotkey.bind(alt, "g", function()
    NanoWM.toggleGaps()
end)
hs.hotkey.bind(altShift, "g", function()
    NanoWM.toggleSketchybar()
end)
hs.hotkey.bind(ctrlAlt, "b", function()
    NanoWM.toggleBorders()
end)
hs.hotkey.bind(ctrlAlt, "p", function()
    NanoWM.toggleBatterySaver()
end)
hs.hotkey.bind(ctrlAlt, "f", function()
    NanoWM.toggleFreeMode()
end)
hs.hotkey.bind(alt, "/", function()
    NanoWM.showKeybindMenu()
end)
hs.hotkey.bind(alt, "u", function()
    NanoWM.gotoUrgent()
end)
hs.hotkey.bind(altShift, "m", function()
    NanoWM.saveCurrentWindowTag()
end)
hs.hotkey.bind(ctrlAltShift, "m", function()
    NanoWM.saveAllWindowTags()
end)
-- Floating window resize keybinds (note: conflicts with swap, only work on floating windows)
hs.hotkey.bind(altShift, "h", function()
    local win = hs.window.focusedWindow()
    if win and NanoWM.isFloating(win) then
        NanoWM.resizeFloatingWindow("narrower")
    else
        NanoWM.swapWindow(-1) -- Fall back to original behavior for tiled windows
    end
end)
hs.hotkey.bind(altShift, "l", function()
    local win = hs.window.focusedWindow()
    if win and NanoWM.isFloating(win) then
        NanoWM.resizeFloatingWindow("wider")
    else
        NanoWM.swapWindow(1) -- Fall back to original behavior for tiled windows
    end
end)
hs.hotkey.bind(altShift, "k", function()
    local win = hs.window.focusedWindow()
    if win and NanoWM.isFloating(win) then
        NanoWM.resizeFloatingWindow("shorter")
    else
        NanoWM.swapWindow(-1) -- Original behavior
    end
end)
hs.hotkey.bind(altShift, "j", function()
    local win = hs.window.focusedWindow()
    if win and NanoWM.isFloating(win) then
        NanoWM.resizeFloatingWindow("taller")
    else
        NanoWM.swapWindow(1) -- Original behavior
    end
end)
hs.hotkey.bind(ctrlAlt, "h", function()
    NanoWM.moveFloatingWindow("left")
end)
hs.hotkey.bind(ctrlAlt, "l", function()
    NanoWM.moveFloatingWindow("right")
end)
hs.hotkey.bind(ctrlAlt, "k", function()
    NanoWM.moveFloatingWindow("up")
end)
hs.hotkey.bind(ctrlAlt, "j", function()
    NanoWM.moveFloatingWindow("down")
end)
hs.hotkey.bind(ctrlAltShift, "s", function()
    NanoWM.toggleSticky()
end)
hs.hotkey.bind(altShift, "space", function()
    NanoWM.toggleFloat()
end)

hs.hotkey.bind(alt, "return", function()
    NanoWM.launchTask("/usr/bin/open", { "-n", "-a", "Alacritty" })
end)
hs.hotkey.bind(alt, "b", function()
    NanoWM.launchTask("/usr/bin/open", { "-n", "-a", "Firefox" })
end)
hs.hotkey.bind(altShift, "return", function()
    hs.application.launchOrFocus("Alacritty")
end)
hs.hotkey.bind(altShift, "b", function()
    hs.application.launchOrFocus("Firefox")
end)
hs.hotkey.bind(alt, "d", function()
    hs.application.launchOrFocus("Raycast")
end)
hs.hotkey.bind(altShift, "v", function()
    hs.task.new("/usr/bin/open", nil, { "raycast://extensions/raycast/clipboard-history/clipboard-history" }):start()
end)

hs.hotkey.bind(altShift, "q", function()
    local w = hs.window.focusedWindow()
    if w then
        w:close()
    end
end)

-- Helper function to find and focus ORGINDEX window, or create new one
function NanoWM.focusOrCreateOrgindex(titlePattern, launchCmd)
    -- Search for existing window with matching title
    -- Use hs.window.allWindows() to get ALL windows including hidden ones
    local allWins = hs.window.allWindows()
    print("[NanoWM] Looking for window with title pattern: " .. titlePattern)
    print("[NanoWM] Total windows found: " .. #allWins)
    for _, win in ipairs(allWins) do
        local title = win:title() or ""
        print("[NanoWM] Checking window: " .. title)
        if string.find(title, titlePattern, 1, true) then
            print("[NanoWM] FOUND matching window!")
            -- Found existing window - move to current tag, raise and focus
            local id = win:id()
            local currentTag = NanoWM.tags[id]
            local targetTag = NanoWM.special.active and NanoWM.special.tag or NanoWM.currentTag

            -- Move to current tag if not already there
            if currentTag ~= targetTag then
                -- Remove from old tag stack
                if currentTag and NanoWM.stacks[currentTag] then
                    for i, vid in ipairs(NanoWM.stacks[currentTag]) do
                        if vid == id then
                            table.remove(NanoWM.stacks[currentTag], i)
                            break
                        end
                    end
                end
                -- Add to new tag
                NanoWM.tags[id] = targetTag
                if not NanoWM.stacks[targetTag] then
                    NanoWM.stacks[targetTag] = {}
                end
                table.insert(NanoWM.stacks[targetTag], 1, id)
                NanoWM.triggerSave()
            end

            -- Raise and focus
            win:raise()
            win:focus()
            NanoWM.tile()
            return
        end
    end

    -- No existing window found - create new one
    print("[NanoWM] No existing window found, creating new one")
    NanoWM.launchTask("/bin/zsh", { "-c", launchCmd })
end

hs.hotkey.bind(altShift, "o", function()
    NanoWM.focusOrCreateOrgindex(
        "ORGINDEX-AGENDA",
        '/Applications/Alacritty.app/Contents/MacOS/alacritty -o "window.dimensions.lines=20" -o "window.dimensions.columns=100" --title "ORGINDEX-AGENDA" -e zsh -c "nvim --cmd \\"cd ~/org/life\\" -c \\"lua require(\\\\\\"orgmode.api.agenda\\\\\\").agenda({span = 1})\\""'
    )
end)
hs.hotkey.bind(altShift, "w", function()
    NanoWM.focusOrCreateOrgindex(
        "ORGINDEX-WORK",
        '/Applications/Alacritty.app/Contents/MacOS/alacritty -o "window.dimensions.lines=20" -o "window.dimensions.columns=100" --title "ORGINDEX-WORK" -e zsh -c "cd ~/org/life && vim ~/org/life/work/work.org"'
    )
end)
hs.hotkey.bind(altShift, "d", function()
    NanoWM.focusOrCreateOrgindex(
        "ORGINDEX-DUMP",
        '/Applications/Alacritty.app/Contents/MacOS/alacritty -o "window.dimensions.lines=20" -o "window.dimensions.columns=100" --title "ORGINDEX-DUMP" -e zsh -c "cd ~/org/life && vim ~/org/life/dump.org"'
    )
end)
hs.hotkey.bind(altShift, "y", function()
    NanoWM.focusOrCreateOrgindex(
        "ORGINDEX-YOUTUBE",
        '/Applications/Alacritty.app/Contents/MacOS/alacritty -o "window.dimensions.lines=20" -o "window.dimensions.columns=100" --title "ORGINDEX-YOUTUBE" -e zsh -c "cd ~/org/consume && vim ~/org/consume/youtube/youtube1.org"'
    )
end)

-- Timer keybindings (Alt+T as prefix, then number)
local timerModal = hs.hotkey.modal.new(alt, "t")
timerModal:bind("", "1", function()
    NanoWM.startTimer(5)
    timerModal:exit()
end)
timerModal:bind("", "2", function()
    NanoWM.startTimer(10)
    timerModal:exit()
end)
timerModal:bind("", "3", function()
    NanoWM.startTimer(60)
    timerModal:exit()
end)
timerModal:bind("", "4", function()
    NanoWM.startTimer(120)
    timerModal:exit()
end)
timerModal:bind("", "n", function()
    timerModal:exit()
    NanoWM.startCustomTimer()
end)
timerModal:bind("", "r", function()
    NanoWM.showTimerRemaining()
    timerModal:exit()
end)
timerModal:bind("", "c", function()
    NanoWM.cancelTimer()
    timerModal:exit()
end)
timerModal:bind("", "escape", function()
    timerModal:exit()
end)

hs.hotkey.bind({ "alt", "shift", "ctrl" }, "r", function()
    hs.reload()
    hs.alert.show("NanoWM v39 Reloaded")
end)
hs.hotkey.bind({ "alt", "shift", "ctrl" }, "c", function()
    hs.toggleConsole()
end)
-- FIXED: AClock toggle with proper initialization and method checking
hs.hotkey.bind({ "cmd", "alt" }, "t", function()
    if clock then
        -- Try different methods that AClock might have
        if clock.toggleShow then
            clock:toggleShow()
        elseif clock.show and clock.hide then
            -- Toggle manually if no toggleShow method
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

-- -----------------------------------------------------------------------------
-- MOUSE RESIZE WATCHER
-- -----------------------------------------------------------------------------
-- Detect when windows are manually resized and update master width accordingly
NanoWM.resizeWatcher = hs.timer.delayed.new(0.3, function()
    NanoWM.handleManualResize()
end)

function NanoWM.handleManualResize()
    -- Skip if fullscreen or monocle mode is active (windows are intentionally full-width)
    if NanoWM.isFullscreen or NanoWM.layout == "monocle" then
        return
    end

    local tag = NanoWM.special.active and NanoWM.special.tag or NanoWM.currentTag

    -- Skip if tag is in free mode
    if NanoWM.isTagFree(tag) then
        return
    end

    local windows = NanoWM.getTiledWindows(tag)

    -- Only handle resize if we have 2+ windows (master + stack)
    if #windows < 2 then
        return
    end

    local screen = hs.screen.mainScreen():frame()
    local masterWin = windows[1]
    local masterFrame = masterWin:frame()

    -- Skip if master window is at full screen width (likely in transition or fullscreen)
    if math.abs(masterFrame.w - screen.w) < 10 then
        return
    end

    -- Calculate the new master width ratio based on the master window's current width
    local newMasterWidth = masterFrame.w / screen.w

    -- Clamp to reasonable bounds
    newMasterWidth = math.max(0.1, math.min(0.9, newMasterWidth))

    -- Only update if significantly different (avoid micro-adjustments)
    local currentWidth = NanoWM.getMasterWidth(tag)
    if math.abs(newMasterWidth - currentWidth) > 0.02 then
        NanoWM.setMasterWidth(tag, newMasterWidth)
    end

    -- Re-tile to ensure all windows fit properly
    NanoWM.tile()
end

filter:subscribe(hs.window.filter.windowMoved, function(win)
    if not win then
        return
    end
    -- Only handle resize for tiled windows, not floating ones
    -- Also skip if tag is in free mode
    local tag = NanoWM.special.active and NanoWM.special.tag or NanoWM.currentTag
    if not NanoWM.isFloating(win) and not NanoWM.isTagFree(tag) then
        NanoWM.resizeWatcher:start()
    end
end)

-- -----------------------------------------------------------------------------
-- -----------------------------------------------------------------------------
-- JANKYBORDERS INTEGRATION (Smart Borders)
-- -----------------------------------------------------------------------------
NanoWM.bordersEnabled = false          -- Disabled by default
NanoWM.bordersCurrentlyShowing = false -- Track actual visibility state

function NanoWM.toggleBorders()
    NanoWM.bordersEnabled = not NanoWM.bordersEnabled
    if NanoWM.bordersEnabled then
        hs.alert.show("Borders: ON (smart mode)")
        NanoWM.updateBordersVisibility()
    else
        hs.alert.show("Borders: OFF")
        NanoWM.stopBorders()
        NanoWM.bordersCurrentlyShowing = false
    end
    NanoWM.triggerSave()
end

function NanoWM.startBorders()
    os.execute("/bin/zsh -l -c \x27$HOME/.config/borders/bordersrc &\x27 &")
end

function NanoWM.stopBorders()
    os.execute("pkill -x borders 2>/dev/null")
end

-- Smart borders: auto-hide when only 1 window or in monocle/fullscreen mode
function NanoWM.updateBordersVisibility()
    if not NanoWM.bordersEnabled then
        return
    end

    local tag = NanoWM.special.active and NanoWM.special.tag or NanoWM.currentTag
    local windows = NanoWM.getTiledWindows(tag)
    local windowCount = #windows

    -- Hide borders if: monocle mode, fullscreen, or only 1 (or 0) tiled window
    local shouldHide = (NanoWM.layout == "monocle") or NanoWM.isFullscreen or (windowCount <= 1)

    if shouldHide and NanoWM.bordersCurrentlyShowing then
        NanoWM.stopBorders()
        NanoWM.bordersCurrentlyShowing = false
    elseif not shouldHide and not NanoWM.bordersCurrentlyShowing then
        NanoWM.startBorders()
        NanoWM.bordersCurrentlyShowing = true
    end
end

-- Restore borders state on startup
local savedBordersEnabled = hs.settings.get("nanoWM_bordersEnabled")
if savedBordersEnabled then
    NanoWM.bordersEnabled = savedBordersEnabled
    -- Delay to let windows settle, then update visibility
    hs.timer.doAfter(2, function()
        NanoWM.updateBordersVisibility()
    end)
end

-- -----------------------------------------------------------------------------
-- BATTERY SAVER MODE
-- -----------------------------------------------------------------------------
NanoWM.batterySaverEnabled = false
NanoWM.batterySaverPreviousState = {} -- Store previous states to restore

function NanoWM.toggleBatterySaver()
    NanoWM.batterySaverEnabled = not NanoWM.batterySaverEnabled

    if NanoWM.batterySaverEnabled then
        -- Save current states before disabling
        NanoWM.batterySaverPreviousState.sketchybar = NanoWM.sketchybarEnabled
        NanoWM.batterySaverPreviousState.borders = NanoWM.bordersEnabled

        -- Stop sketchybar completely (not just hide)
        os.execute("pkill -x sketchybar 2>/dev/null")
        NanoWM.sketchybarEnabled = false

        -- Stop borders
        NanoWM.stopBorders()
        NanoWM.bordersEnabled = false
        NanoWM.bordersCurrentlyShowing = false

        hs.alert.show("🔋 Battery Saver: ON\nSketchybar & Borders disabled", 2)
    else
        -- Restore previous states
        if NanoWM.batterySaverPreviousState.sketchybar then
            os.execute("/bin/zsh -l -c \x27sketchybar &\x27 &")
            NanoWM.sketchybarEnabled = true
            hs.timer.doAfter(1, function()
                NanoWM.updateSketchybar()
            end)
        end

        if NanoWM.batterySaverPreviousState.borders then
            NanoWM.bordersEnabled = true
            NanoWM.updateBordersVisibility()
        end

        hs.alert.show("⚡ Battery Saver: OFF\nFeatures restored", 2)
    end

    NanoWM.triggerSave()
end

-- -----------------------------------------------------------------------------
NanoWM.sketchybarEnabled = false -- Disabled by default, use Alt+Shift+G to enable

-- Debounced sketchybar update to prevent too many calls
NanoWM.sketchybarUpdateTimer = nil

function NanoWM.updateSketchybar()
    if not NanoWM.sketchybarEnabled then
        return
    end

    -- Debounce: cancel pending update and schedule a new one
    if NanoWM.sketchybarUpdateTimer then
        NanoWM.sketchybarUpdateTimer:stop()
    end

    NanoWM.sketchybarUpdateTimer = hs.timer.doAfter(0.02, function()
        NanoWM.doUpdateSketchybar()
    end)
end

function NanoWM.updateSketchybarNow()
    if not NanoWM.sketchybarEnabled then
        return
    end
    NanoWM.doUpdateSketchybar()
end

function NanoWM.doUpdateSketchybar()
    -- Get current tag info
    local tag = NanoWM.special.active and "S" or tostring(NanoWM.currentTag)
    local windowCount = #NanoWM.getTiledWindows(NanoWM.special.active and NanoWM.special.tag or NanoWM.currentTag)
    local layout = NanoWM.layout
    local isFullscreen = NanoWM.isFullscreen and "1" or "0"

    -- Get list of occupied tags (tags that have windows)
    local occupiedTags = {}
    for i = 1, 10 do
        local wins = NanoWM.getTiledWindows(i)
        if #wins > 0 then
            table.insert(occupiedTags, tostring(i))
        end
    end
    -- Check special tag
    local specialWins = NanoWM.getTiledWindows("special")
    if #specialWins > 0 then
        table.insert(occupiedTags, "S")
    end
    local occupied = table.concat(occupiedTags, " ")

    -- Get timer info
    local timerRemaining = ""
    if NanoWM.timerEndTime then
        local remaining = NanoWM.timerEndTime - os.time()
        if remaining > 0 then
            local mins = math.floor(remaining / 60)
            local secs = remaining % 60
            timerRemaining = string.format("%d:%02d", mins, secs)
        end
    end

    -- Get focused app name
    local focusedApp = ""
    local focusedWin = hs.window.focusedWindow()
    if focusedWin and focusedWin:application() then
        focusedApp = focusedWin:application():name() or ""
    end

    -- Get list of urgent tags
    local urgentList = {}
    for urgentTag, _ in pairs(NanoWM.urgentTags) do
        if urgentTag == "special" then
            table.insert(urgentList, "S")
        else
            table.insert(urgentList, tostring(urgentTag))
        end
    end
    local urgent = table.concat(urgentList, " ")

    -- Send to sketchybar via trigger (async to avoid blocking)
    local cmd = string.format(
        'sketchybar --trigger nanowm_update TAG="%s" WINDOWS="%d" LAYOUT="%s" FULLSCREEN="%s" TIMER="%s" APP="%s" OCCUPIED="%s" URGENT="%s" 2>/dev/null',
        tag,
        windowCount,
        layout,
        isFullscreen,
        timerRemaining,
        focusedApp,
        occupied,
        urgent
    )
    -- Use hs.task for async execution (fire and forget)
    hs.task.new("/bin/zsh", nil, { "-c", cmd }):start()
end

function NanoWM.toggleSketchybar()
    -- First check if sketchybar is running
    hs.task
        .new("/bin/zsh", function(exitCode, stdOut, stdErr)
            if exitCode ~= 0 then
                -- Sketchybar not running, start it
                -- Use login shell to get full environment (nix paths, config dirs, etc.)
                os.execute("/bin/zsh -l -c 'sketchybar &' &")
                NanoWM.sketchybarEnabled = true
                hs.alert.show("Sketchybar: ON (started)")
                -- Give it a moment to start, then update
                hs.timer.doAfter(1, function()
                    NanoWM.updateSketchybar()
                end)
            else
                -- Sketchybar is running, toggle visibility
                hs.task
                    .new("/bin/zsh", function()
                        NanoWM.sketchybarEnabled = not NanoWM.sketchybarEnabled
                        hs.alert.show("Sketchybar: " .. (NanoWM.sketchybarEnabled and "ON" or "OFF"))
                        if NanoWM.sketchybarEnabled then
                            NanoWM.updateSketchybar()
                        end
                    end, { "-c", "sketchybar --bar hidden=toggle" })
                    :start()
            end
        end, { "-c", "pgrep -x sketchybar" })
        :start()
end

-- Update sketchybar periodically for timer countdown
NanoWM.sketchybarTimer = hs.timer.new(1, function()
    if NanoWM.timerEndTime and NanoWM.sketchybarEnabled then
        NanoWM.updateSketchybar()
    end
end)
-- NanoWM.sketchybarTimer:start() -- Only start when timer is active

-- Restore sketchybar state and restart it
local savedSketchybarEnabled = hs.settings.get("nanoWM_sketchybarEnabled")
if savedSketchybarEnabled ~= nil then
    NanoWM.sketchybarEnabled = savedSketchybarEnabled
end

-- Restart sketchybar on Hammerspoon reload
hs.task
    .new("/bin/zsh", function(exitCode, stdOut, stdErr)
        if exitCode == 0 then
            -- Sketchybar is running, kill it first
            os.execute("pkill -x sketchybar")
            hs.timer.doAfter(0.5, function()
                -- Start sketchybar fresh
                os.execute("/bin/zsh -l -c 'sketchybar &' &")
                hs.timer.doAfter(2, function()
                    -- Restore hidden state
                    if not NanoWM.sketchybarEnabled then
                        os.execute("sketchybar --bar hidden=true")
                    else
                        -- Send multiple updates to ensure sketchybar receives them
                        NanoWM.updateSketchybar()
                        hs.timer.doAfter(0.5, function()
                            NanoWM.updateSketchybar()
                        end)
                    end
                end)
            end)
        else
            -- Sketchybar not running, start it if it was enabled
            if NanoWM.sketchybarEnabled then
                os.execute("/bin/zsh -l -c 'sketchybar &' &")
                hs.timer.doAfter(2, function()
                    NanoWM.updateSketchybar()
                    hs.timer.doAfter(0.5, function()
                        NanoWM.updateSketchybar()
                    end)
                end)
            end
        end
    end, { "-c", "pgrep -x sketchybar" })
    :start()

NanoWM.tile()
hs.alert.show("NanoWM v39 Started")
