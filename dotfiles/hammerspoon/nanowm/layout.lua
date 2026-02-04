-- =============================================================================
-- NanoWM Layout Engine
-- Tiling logic, window positioning, and layout management
-- =============================================================================

local config = require("nanowm.config")
local state = require("nanowm.state")
local core = require("nanowm.core")

local M = {}

-- Forward declarations for integration callbacks
M.onTileComplete = nil  -- Set by integrations module

-- =============================================================================
-- Debounced Tile Timer
-- =============================================================================

local tileTimer = hs.timer.delayed.new(0.02, function()
    M.performTile()
end)

function M.tile()
    tileTimer:start()
end

-- =============================================================================
-- Raise Floating Windows
-- =============================================================================

function M.raiseFloating()
    local tag = state.special.active and state.special.tag or state.currentTag

    local floatingWins = {}
    for _, win in ipairs(hs.window.filter.default:getWindows()) do
        local id = win:id()
        local winTag = state.tags[id]
        local isSticky = state.sticky[id]
        local isPip = (win:title() == "Picture-in-Picture")
        local isFloat = core.isFloating(win)

        local isVisible = false
        if winTag == state.currentTag then isVisible = true end
        if state.special.active and winTag == state.special.tag then isVisible = true end
        if isSticky or isPip then isVisible = true end

        if isFloat and not isSticky and not isPip and winTag ~= state.currentTag and winTag ~= state.special.tag then
            isVisible = false
        end

        if isVisible and isFloat then
            if win:frame().x < 90000 then
                table.insert(floatingWins, win)
            end
        end
    end

    for _, win in ipairs(floatingWins) do
        win:raise()
    end

    if state.special.active then
        local specialWins = core.getTiledWindows(state.special.tag)
        for _, win in ipairs(specialWins) do
            if win:frame().x < 90000 then
                win:raise()
            end
        end
    end
end

-- =============================================================================
-- Main Tile Function
-- =============================================================================

function M.performTile()
    state.lastTileTime = hs.timer.secondsSinceEpoch()

    local screen = hs.screen.mainScreen()
    local frame = screen:frame()

    if state.sketchybarEnabled then
        local name = screen:name()
        -- Adjust for SketchyBar on external monitors (assuming non-built-in are external)
        -- Common built-in names: "Built-in Retina Display", "Color LCD"
        if name ~= "Built-in Retina Display" and name ~= "Color LCD" then
            frame.y = frame.y + config.sketchybarHeight
            frame.h = frame.h - config.sketchybarHeight
        end
    end

    local toHide = {}
    local toFloat = {}

    -- PHASE 1: CLASSIFICATION
    for _, win in ipairs(hs.window.filter.default:getWindows()) do
        local id = win:id()
        core.registerWindow(win)

        local winTag = state.tags[id]
        local isSticky = state.sticky[id]
        local isPip = (win:title() == "Picture-in-Picture")
        local isFloat = core.isFloating(win)

        local isVisible = false
        if winTag == state.currentTag then isVisible = true end
        if state.special.active and winTag == state.special.tag then isVisible = true end
        if isSticky or isPip then isVisible = true end

        if isFloat and not isSticky and not isPip and winTag ~= state.currentTag and winTag ~= state.special.tag then
            isVisible = false
        end

        if not state.windowState[id] then
            state.windowState[id] = { isHidden = false }
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

        if not state.windowState[id].isHidden and core.isFloating(win) then
            local f = win:frame()
            if f.x < 10000 then
                state.floatingCache[idStr] = { x = f.x, y = f.y, w = f.w, h = f.h }
            end
        end

        local f = win:frame()
        if f.x < 90000 then
            local screenFrame = hs.screen.mainScreen():frame()
            f.x = screenFrame.x + screenFrame.w - 5
            f.y = screenFrame.y + screenFrame.h - 5
            win:setFrame(f)
            state.windowState[id].isHidden = true
        end
    end

    -- PHASE 3: TILE BACKGROUND
    local backgroundWindows = core.getTiledWindows(state.currentTag)
    if not state.isTagFree(state.currentTag) then
        M.applyLayout(backgroundWindows, frame, false, state.currentTag)
    else
        for _, win in ipairs(backgroundWindows) do
            local id = win:id()
            if state.windowState[id] and state.windowState[id].isHidden then
                local cached = state.freeTagPositions[state.currentTag] and state.freeTagPositions[state.currentTag][id]
                if cached then
                    win:setFrame(cached)
                else
                    win:centerOnScreen()
                end
                state.windowState[id].isHidden = false
            end
        end
    end

    -- PHASE 3.5: TILE SPECIAL TAG
    if state.special.active then
        local specialWindows = core.getTiledWindows(state.special.tag)
        if not state.isTagFree(state.special.tag) then
            local pad = config.specialPadding
            local specialFrame = {
                x = frame.x + pad,
                y = frame.y + pad,
                w = frame.w - (pad * 2),
                h = frame.h - (pad * 2)
            }
            M.applyLayout(specialWindows, specialFrame, true, state.special.tag)
        else
            for _, win in ipairs(specialWindows) do
                local id = win:id()
                if state.windowState[id] and state.windowState[id].isHidden then
                    local cached = state.freeTagPositions[state.special.tag] and state.freeTagPositions[state.special.tag][id]
                    if cached then
                        win:setFrame(cached)
                    else
                        win:centerOnScreen()
                    end
                    state.windowState[id].isHidden = false
                end
            end
        end

        for _, win in ipairs(specialWindows) do
            win:raise()
        end
    end

    -- PHASE 4: FLOAT RESTORE
    for _, win in ipairs(toFloat) do
        local id = win:id()
        local idStr = tostring(id)

        if state.windowState[id].isHidden or win:frame().x >= 90000 then
            local saved = state.floatingCache[idStr]
            if saved and saved.x < 10000 then
                win:setFrame(saved)
            else
                win:centerOnScreen()
            end
            state.windowState[id].isHidden = false
            win:raise()
        end
    end

    -- PHASE 5: ENSURE SPECIAL WINDOWS ON TOP
    if state.special.active then
        hs.timer.doAfter(0.05, function()
            local specialWins = core.getTiledWindows(state.special.tag)
            for _, win in ipairs(specialWins) do
                if win:frame().x < 90000 then
                    win:raise()
                end
            end
        end)
    end

    -- Call integration callbacks
    if M.onTileComplete then
        M.onTileComplete()
    end
end

-- =============================================================================
-- Apply Layout
-- =============================================================================

function M.applyLayout(windows, area, isSpecial, tag)
    local count = #windows
    if count == 0 then return end

    local gap = state.gap

    local function setFrameSmart(win, newFrame)
        local f = win:frame()
        if math.abs(f.x - newFrame.x) > 1 or
           math.abs(f.y - newFrame.y) > 1 or
           math.abs(f.w - newFrame.w) > 1 or
           math.abs(f.h - newFrame.h) > 1 then
            win:setFrame(newFrame)
        end
    end

    -- Fullscreen mode
    if state.isFullscreen and not isSpecial then
        for _, win in ipairs(windows) do
            setFrameSmart(win, hs.screen.mainScreen():frame())
        end
        return
    end

    -- Monocle layout
    if state.layout == "monocle" then
        for _, win in ipairs(windows) do
            setFrameSmart(win, area)
        end
        return
    end

    -- Tile layout
    local masterWin = windows[1]
    if count == 1 then
        setFrameSmart(masterWin, {
            x = area.x + gap,
            y = area.y + gap,
            w = area.w - (2 * gap),
            h = area.h - (2 * gap)
        })
    else
        local masterWidth = state.getMasterWidth(tag)
        local mw = math.floor(area.w * masterWidth)
        setFrameSmart(masterWin, {
            x = area.x + gap,
            y = area.y + gap,
            w = mw - (1.5 * gap),
            h = area.h - (2 * gap)
        })

        local sx = area.x + mw + (0.5 * gap)
        local sw = area.w - mw - (1.5 * gap)
        local sh = (area.h - (gap * count)) / (count - 1)

        for i = 2, count do
            setFrameSmart(windows[i], {
                x = sx,
                y = area.y + gap + ((i - 2) * (sh + gap)),
                w = sw,
                h = sh
            })
        end
    end
end

-- =============================================================================
-- Manual Resize Handler
-- =============================================================================

function M.handleManualResize()
    if state.isFullscreen or state.layout == "monocle" then
        return
    end

    local tag = state.special.active and state.special.tag or state.currentTag

    if state.isTagFree(tag) then
        return
    end

    local windows = core.getTiledWindows(tag)
    if #windows < 2 then
        return
    end

    local screen = hs.screen.mainScreen():frame()
    local masterWin = windows[1]
    local masterFrame = masterWin:frame()

    if math.abs(masterFrame.w - screen.w) < 10 then
        return
    end

    local newMasterWidth = masterFrame.w / screen.w
    newMasterWidth = math.max(0.1, math.min(0.9, newMasterWidth))

    local currentWidth = state.getMasterWidth(tag)
    if math.abs(newMasterWidth - currentWidth) > 0.02 then
        state.setMasterWidth(tag, newMasterWidth)
    end

    M.tile()
end

return M
