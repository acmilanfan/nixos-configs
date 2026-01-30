require("macos-vim-navigation/init")

local clock = hs.loadSpoon("AClock")

local VimMode = hs.loadSpoon("VimMode")
local vim = VimMode:new()
vim:bindHotKeys({ enter = { { "alt" }, "e" } })
-- vim:enterWithSequence("jk")
--

-- TODO: things to fix/improve
-- sketchybar: add time and day of the week on the right
-- sketchybar: wifi showing <redacted>
-- sketchybar: add cpu monitoring graph

-- =============================================================================
-- BASE SETTINGS
-- =============================================================================
hs.window.animationDuration = 0
hs.ipc.cliInstall()

-- =============================================================================
-- NANOWM v37: Urgent Tags & Tag Switch Cooldown
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

NanoWM.loadState()

NanoWM.currentTag = hs.settings.get("nanoWM_currentTag") or 1
NanoWM.prevTag = hs.settings.get("nanoWM_prevTag") or 1
NanoWM.masterWidths = {} -- Per-tag master widths
NanoWM.defaultMasterWidth = 0.5
NanoWM.gap = 0           -- UPDATED: Default 0
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
NanoWM.urgentTags = {}           -- Table of urgent tags: { [tag] = true }
NanoWM.lastManualTagSwitch = 0   -- Timestamp of last manual tag switch
NanoWM.tagSwitchCooldown = 0.5   -- Cooldown in seconds after manual switch

-- Apps that should trigger urgent (browsers, communication apps)
NanoWM.urgentApps = {
    ["Firefox"] = true,
    ["Safari"] = true,
    ["Google Chrome"] = true,
    ["Arc"] = true,
    ["Slack"] = true,
    ["Discord"] = true,
    ["Messages"] = true,
    ["Telegram"] = true,
    ["WhatsApp"] = true,
    ["Microsoft Teams"] = true,
    ["Zoom"] = true,
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
-- URGENT TAG FUNCTIONS
-- -----------------------------------------------------------------------------
function NanoWM.markTagUrgent(tag)
    -- Don't mark current tag as urgent
    if tag == NanoWM.currentTag then
        return
    end
    if tag == NanoWM.special.tag and NanoWM.special.active then
        return
    end

    if not NanoWM.urgentTags[tag] then
        NanoWM.urgentTags[tag] = true
        NanoWM.updateSketchybar()
        -- Optional: play a subtle sound or show notification
        -- hs.sound.getByName("Tink"):play()
    end
end

function NanoWM.clearUrgent(tag)
    if NanoWM.urgentTags[tag] then
        NanoWM.urgentTags[tag] = nil
        NanoWM.updateSketchybar()
    end
end

function NanoWM.gotoUrgent()
    -- Find first urgent tag and go to it
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
        local targetTag = NanoWM.special.active and NanoWM.special.tag or NanoWM.currentTag
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
        if win and win:isVisible() then
            if not NanoWM.isFloating(win) then
                table.insert(windows, win)
                table.insert(cleanStack, id)
            end
        elseif hs.window.get(id) then
            table.insert(cleanStack, id)
        end
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

    -- PHASE 3: TILE BACKGROUND
    local backgroundWindows = NanoWM.getTiledWindows(NanoWM.currentTag)
    NanoWM.applyLayout(backgroundWindows, frame, false, NanoWM.currentTag)

    if NanoWM.special.active then
        local specialWindows = NanoWM.getTiledWindows(NanoWM.special.tag)
        local pad = 100
        local specialFrame = { x = frame.x + pad, y = frame.y + pad, w = frame.w - (pad * 2), h = frame.h - (pad * 2) }
        NanoWM.applyLayout(specialWindows, specialFrame, true, NanoWM.special.tag)

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

    -- Update sketchybar with current state
    NanoWM.updateSketchybar()
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
                t = "Reset Tags",
                fn = function()
                    NanoWM.tags = {}
                    NanoWM.stacks = {}
                    NanoWM.sticky = {}
                    NanoWM.floatingOverrides = {}
                    NanoWM.currentTag = 1
                    NanoWM.saveState()
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
    NanoWM.updateSketchybarNow()  -- Immediate update for responsive feel
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
    local currentTag = NanoWM.tags[win:id()]
    if currentTag and NanoWM.stacks[currentTag] then
        for i, id in ipairs(NanoWM.stacks[currentTag]) do
            if id == win:id() then
                table.remove(NanoWM.stacks[currentTag], i)
                break
            end
        end
    end
    NanoWM.tags[win:id()] = destTag
    if not NanoWM.stacks[destTag] then
        NanoWM.stacks[destTag] = {}
    end
    table.insert(NanoWM.stacks[destTag], 1, win:id())
    -- Reset master width if only one window left on the source tag
    if currentTag then
        NanoWM.resetMasterWidthIfNeeded(currentTag)
    end

    NanoWM.triggerSave()
    NanoWM.tile()
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
        local idStr = tostring(id)
        local tag = NanoWM.tags[id]
        if tag and NanoWM.stacks[tag] then
            for i, vid in ipairs(NanoWM.stacks[tag]) do
                if vid == id then
                    table.remove(NanoWM.stacks[tag], i)
                    break
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

        NanoWM.triggerSave()
    end
    if NanoWM.focusTimer then
        NanoWM.focusTimer:stop()
        NanoWM.focusTimer = nil
    end
    local currentWins = NanoWM.getTiledWindows(NanoWM.currentTag)
    if #currentWins > 0 then
        currentWins[1]:focus()
    end
    NanoWM.tile()
end)

filter:subscribe(hs.window.filter.windowFocused, function(win)
    if not win then
        return
    end
    if NanoWM.launching then
        return
    end

    -- Only raise THIS floating window, not all of them
    if NanoWM.isFloating(win) then
        win:raise()
        return
    end

    local id = win:id()
    local tag = NanoWM.tags[id]
    if not tag or tag == NanoWM.currentTag or tag == "special" then
        return
    end

    -- Check if we're within the cooldown period after a manual tag switch
    local timeSinceManualSwitch = hs.timer.secondsSinceEpoch() - NanoWM.lastManualTagSwitch
    if timeSinceManualSwitch < NanoWM.tagSwitchCooldown then
        -- Within cooldown, don't auto-switch, just mark as urgent
        local app = win:application()
        if app and NanoWM.urgentApps[app:name()] then
            NanoWM.markTagUrgent(tag)
        end
        return
    end

    -- Outside cooldown - mark tag as urgent instead of auto-switching
    -- This gives user control over when to switch
    local app = win:application()
    if app and NanoWM.urgentApps[app:name()] then
        NanoWM.markTagUrgent(tag)
        -- Cancel any pending focus timer
        if NanoWM.focusTimer then
            NanoWM.focusTimer:stop()
            NanoWM.focusTimer = nil
        end
        return
    end

    -- For non-urgent apps, use the original delayed switch behavior
    if NanoWM.focusTimer then
        NanoWM.focusTimer:stop()
    end
    NanoWM.focusTimer = hs.timer.doAfter(0.2, function()
        NanoWM.gotoTag(tag)
        NanoWM.focusTimer = nil
    end)
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
    end)

    NanoWM.updateSketchybar()
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
    local keybinds = {
        {
            category = "Navigation",
            binds = {
                { key = "Alt+J", desc = "Focus next window" },
                { key = "Alt+K", desc = "Focus previous window" },
                { key = "Alt+H", desc = "Decrease master width" },
                { key = "Alt+L", desc = "Increase master width" },
            },
        },
        {
            category = "Window Management",
            binds = {
                { key = "Alt+Shift+J",      desc = "Swap window down" },
                { key = "Alt+Shift+K",      desc = "Swap window up" },
                { key = "Alt+F",            desc = "Toggle fullscreen" },
                { key = "Alt+C",            desc = "Center window" },
                { key = "Alt+Shift+C",      desc = "Resize floating to 60%" },
                { key = "Alt+Shift+Space",  desc = "Toggle float" },
                { key = "Ctrl+Alt+Shift+S", desc = "Toggle sticky" },
                { key = "Alt+Shift+Q",      desc = "Close window" },
            },
        },
        {
            category = "Floating Window Resize",
            binds = {
                { key = "Alt+Shift+H", desc = "Make narrower" },
                { key = "Alt+Shift+L", desc = "Make wider" },
                { key = "Alt+Shift+K", desc = "Make shorter" },
                { key = "Alt+Shift+J", desc = "Make taller" },
            },
        },
        {
            category = "Floating Window Move",
            binds = {
                { key = "Ctrl+Alt+H", desc = "Move left" },
                { key = "Ctrl+Alt+L", desc = "Move right" },
                { key = "Ctrl+Alt+K", desc = "Move up" },
                { key = "Ctrl+Alt+J", desc = "Move down" },
            },
        },
        {
            category = "Tags",
            binds = {
                { key = "Alt+1-9/0",       desc = "Go to tag 1-10" },
                { key = "Alt+Shift+1-9/0", desc = "Move window to tag" },
                { key = "Alt+Escape",      desc = "Toggle previous tag" },
                { key = "Alt+S",           desc = "Toggle special tag" },
                { key = "Alt+Shift+S",     desc = "Move to special tag" },
                { key = "Alt+U",           desc = "Go to urgent tag" },
            },
        },
        {
            category = "Layout & Display",
            binds = {
                { key = "Cmd+Space", desc = "Toggle layout (tile/monocle)" },
                { key = "Alt+G",     desc = "Toggle gaps" },
            },
        },
        {
            category = "Menus",
            binds = {
                { key = "Alt+M", desc = "App menu palette" },
                { key = "Alt+P", desc = "Commands menu" },
                { key = "Alt+I", desc = "Windows menu" },
                { key = "Alt+/", desc = "This keybind menu" },
            },
        },
        {
            category = "Applications",
            binds = {
                { key = "Alt+Return",       desc = "New Alacritty" },
                { key = "Alt+Shift+Return", desc = "Focus Alacritty" },
                { key = "Alt+B",            desc = "New Firefox" },
                { key = "Alt+Shift+B",      desc = "Focus Firefox" },
                { key = "Alt+D",            desc = "Launch Raycast" },
            },
        },
        {
            category = "Timers",
            binds = {
                { key = "Alt+T, then 1", desc = "5 min timer" },
                { key = "Alt+T, then 2", desc = "10 min timer" },
                { key = "Alt+T, then 3", desc = "60 min timer" },
                { key = "Alt+T, then 4", desc = "120 min timer" },
                { key = "Alt+T, then N", desc = "Custom timer" },
            },
        },
        {
            category = "System",
            binds = {
                { key = "Cmd+Alt+T",        desc = "Toggle AClock" },
                { key = "Ctrl+Alt+Shift+R", desc = "Reload config" },
            },
        },
    }

    local choices = {}
    for _, section in ipairs(keybinds) do
        table.insert(choices, {
            text = "━━━ " .. section.category .. " ━━━",
            subText = "",
            uuid = "header_" .. section.category,
        })
        for _, bind in ipairs(section.binds) do
            table.insert(choices, {
                text = bind.key,
                subText = bind.desc,
                uuid = "bind_" .. bind.key,
            })
        end
    end

    local chooser = hs.chooser.new(function() end)
    chooser:width(50)
    chooser:bgDark(true)
    chooser:fgColor({ hex = "#FFFFFF" })
    chooser:subTextColor({ hex = "#CCCCCC" })
    chooser:choices(choices)
    chooser:placeholderText("Search keybinds by key or description...")
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
-- NEW: Resize floating to 60% centered
hs.hotkey.bind(altShift, "c", function()
    NanoWM.resizeFloatingTo60()
end)
-- NEW: Toggle gaps
hs.hotkey.bind(alt, "g", function()
    NanoWM.toggleGaps()
end)
-- Toggle sketchybar
hs.hotkey.bind(altShift, "g", function()
    NanoWM.toggleSketchybar()
end)
-- NEW: Show keybind menu
hs.hotkey.bind(alt, "/", function()
    NanoWM.showKeybindMenu()
end)
-- NEW: Go to urgent tag
hs.hotkey.bind(alt, "u", function()
    NanoWM.gotoUrgent()
end)
-- NEW: Floating window resize keybinds (note: conflicts with swap, only work on floating windows)
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
-- NEW: Floating window move keybinds
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
    NanoWM.focusOrCreateOrgindex("ORGINDEX-AGENDA",
        '/Applications/Alacritty.app/Contents/MacOS/alacritty -o "window.dimensions.lines=20" -o "window.dimensions.columns=100" --title "ORGINDEX-AGENDA" -e zsh -c "nvim --cmd \\"cd ~/org/life\\" -c \\"lua require(\\\\\\"orgmode.api.agenda\\\\\\").agenda({span = 1})\\""')
end)
hs.hotkey.bind(altShift, "w", function()
    NanoWM.focusOrCreateOrgindex("ORGINDEX-WORK",
        '/Applications/Alacritty.app/Contents/MacOS/alacritty -o "window.dimensions.lines=20" -o "window.dimensions.columns=100" --title "ORGINDEX-WORK" -e zsh -c "cd ~/org/life && vim ~/org/life/work/work.org"')
end)
hs.hotkey.bind(altShift, "d", function()
    NanoWM.focusOrCreateOrgindex("ORGINDEX-DUMP",
        '/Applications/Alacritty.app/Contents/MacOS/alacritty -o "window.dimensions.lines=20" -o "window.dimensions.columns=100" --title "ORGINDEX-DUMP" -e zsh -c "cd ~/org/life && vim ~/org/life/dump.org"')
end)
hs.hotkey.bind(altShift, "y", function()
    NanoWM.focusOrCreateOrgindex("ORGINDEX-YOUTUBE",
        '/Applications/Alacritty.app/Contents/MacOS/alacritty -o "window.dimensions.lines=20" -o "window.dimensions.columns=100" --title "ORGINDEX-YOUTUBE" -e zsh -c "cd ~/org/consume && vim ~/org/consume/youtube/youtube1.org"')
end)

-- NEW: Timer keybindings (Alt+T as prefix, then number)
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
    hs.alert.show("NanoWM v37 Reloaded")
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
    if not NanoWM.isFloating(win) then
        NanoWM.resizeWatcher:start()
    end
end)

-- -----------------------------------------------------------------------------
-- SKETCHYBAR INTEGRATION
-- -----------------------------------------------------------------------------
NanoWM.sketchybarEnabled = false  -- Disabled by default, use Alt+Shift+G to enable

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
    hs.task.new("/bin/zsh", function(exitCode, stdOut, stdErr)
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
            hs.task.new("/bin/zsh", function()
                NanoWM.sketchybarEnabled = not NanoWM.sketchybarEnabled
                hs.alert.show("Sketchybar: " .. (NanoWM.sketchybarEnabled and "ON" or "OFF"))
                if NanoWM.sketchybarEnabled then
                    NanoWM.updateSketchybar()
                end
            end, { "-c", "sketchybar --bar hidden=toggle" }):start()
        end
    end, { "-c", "pgrep -x sketchybar" }):start()
end

-- Update sketchybar periodically for timer countdown
NanoWM.sketchybarTimer = hs.timer.new(1, function()
    if NanoWM.timerEndTime and NanoWM.sketchybarEnabled then
        NanoWM.updateSketchybar()
    end
end)
NanoWM.sketchybarTimer:start()

NanoWM.tile()
NanoWM.updateSketchybar()
hs.alert.show("NanoWM v37 Started")
