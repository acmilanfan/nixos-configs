-- =============================================================================
-- NanoWM Layout Engine
-- Tiling logic, window positioning, and layout management
-- =============================================================================

local config = require("nanowm.config")
local state = require("nanowm.state")
local core = require("nanowm.core")

local M = {}

-- Forward declarations for integration callbacks
M.onTileComplete = nil -- Set by integrations module

-- =============================================================================
-- Debounced Tile Timer
-- =============================================================================

-- local tileTimer = hs.timer.delayed.new(0.15, function()
local tileTimer = hs.timer.delayed.new(0.08, function()
    M.performTile()
end)

-- Reusable timer for raising special-tag windows after tile settles
local specialRaiseTimer -- forward-declared so the callback can close over it
specialRaiseTimer = hs.timer.delayed.new(0.1, function()
    -- Get all windows assigned to the special tag
    local function raiseAll()
        for _, win in ipairs(require("nanowm.watchers").getManagedWindows()) do
            local id = win:id()
            local onSpecial = (state.tags[id] == state.special.tag)
            local isSummoned = (state.lastIntendedFocusId == id)

            if onSpecial or isSummoned then
                if win:frame().x < 90000 then win:raise() end
            end
        end
    end

    raiseAll()
    -- Second pass to ensure they stay on top of any late-activations
    hs.timer.doAfter(0.1, raiseAll)
end)

function M.tile()
    tileTimer:start()
end

-- =============================================================================
-- Raise Floating Windows
-- =============================================================================

function M.raiseFloating()
    local floatingWins = {}
    for _, win in ipairs(require("nanowm.watchers").getManagedWindows()) do
        local id = win:id()
        local winTag = state.tags[id]
        local isSticky = state.sticky[id]
        local isPip = (win:title() == "Picture-in-Picture")
        local isFloat = core.isFloating(win)

        local isVisible = false
        if winTag == state.currentTag then
            isVisible = true
        end
        if state.special.active and winTag == state.special.tag then
            isVisible = true
        end
        if isSticky or isPip then
            isVisible = true
        end

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
    if not screen then return end

    local frame = screen:frame()
    if not frame or frame.w <= 0 or frame.h <= 0 then return end

    if state.sketchybarEnabled then
        local name = screen:name()
        if name ~= "Built-in Retina Display" and name ~= "Color LCD" then
            frame.y = frame.y + config.sketchybarHeight
            frame.h = frame.h - config.sketchybarHeight
        end
    end

    local allWins = require("nanowm.watchers").getManagedWindows()
    local toHide = {}
    local toFloat = {}

    -- PHASE 1: CLASSIFICATION
    for _, win in ipairs(allWins) do
        local id = win:id()
        if not state.tags[id] then
            core.registerWindow(win)
        end

        local winTag = state.tags[id]
        local isSticky = state.sticky[id]
        local isPip = (win:title() == "Picture-in-Picture")
        local isFloat = core.isFloating(win)

        local isVisible = false
        if winTag == state.currentTag then
            isVisible = true
        end
        if state.special.active and winTag == state.special.tag then
            isVisible = true
        end
        if isSticky or isPip then
            isVisible = true
        end

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
    -- Hoist screen frame lookup out of the loop (same for all windows)
    local hideScreenFrame = screen:frame()
    for _, win in ipairs(toHide) do
        local id = win:id()
        local idStr = tostring(id)
        local f = win:frame()

        -- If it's on-screen but shouldn't be: hide it
        if f.x < 90000 then
            if f.w > 0 and f.h > 0 then
                -- Save floating position before hiding (only if visibly on-screen)
                if core.isFloating(win) and f.x < 10000 then
                    state.floatingCache[idStr] = { x = f.x, y = f.y, w = f.w, h = f.h }
                end

                -- Park off-screen
                f.x = hideScreenFrame.x + hideScreenFrame.w - 5
                f.y = hideScreenFrame.y + hideScreenFrame.h - 5
                win:setFrame(f)
            end
        end
        state.windowState[id].isHidden = true
    end

    -- PHASE 3: TILE BACKGROUND
    local backgroundWindows = core.getTiledWindows(state.currentTag, allWins)
    if not state.isTagFree(state.currentTag) then
        M.applyLayout(backgroundWindows, frame, false, state.currentTag, allWins)
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
        local specialWindows = core.getTiledWindows(state.special.tag, allWins)
        if not state.isTagFree(state.special.tag) then
            local pad = config.specialPadding
            local specialFrame = {
                x = frame.x + pad,
                y = frame.y + pad,
                w = math.max(100, frame.w - (pad * 2)),
                h = math.max(100, frame.h - (pad * 2)),
            }
            M.applyLayout(specialWindows, specialFrame, true, state.special.tag, allWins)
        else
            for _, win in ipairs(specialWindows) do
                local id = win:id()
                if state.windowState[id] and state.windowState[id].isHidden then
                    local cached = state.freeTagPositions[state.special.tag]
                        and state.freeTagPositions[state.special.tag][id]
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
        local onSpecial = (state.tags[id] == state.special.tag)
        local shouldRaise = state.windowState[id].isHidden or win:frame().x >= 90000 or (state.lastIntendedFocusId == id) or onSpecial

        if shouldRaise then
            if state.windowState[id].isHidden or win:frame().x >= 90000 then
                local saved = state.floatingCache[idStr]
                if saved and saved.x < 10000 and saved.w > 0 and saved.h > 0 then
                    win:setFrame(saved)
                else
                    win:centerOnScreen()
                end
            end
            state.windowState[id].isHidden = false
            win:raise()
        end
    end

    -- PHASE 5: ENSURE SPECIAL WINDOWS ON TOP
    if state.special.active then
        specialRaiseTimer:start()
    end

    -- Call integration callbacks
    if M.onTileComplete then
        M.onTileComplete()
    end
end

-- =============================================================================
-- Apply Layout
-- =============================================================================

function M.applyLayout(windows, area, isSpecial, tag, allWins)
    local count = #windows
    if count == 0 then
        return
    end

    local currentLayout = state.getLayout(tag)
    local innerGap = state.gap
    local screenGap = 0
    -- Only add screen gaps if borders are enabled and we are in a tiled layout with multiple windows
    if state.bordersEnabled and not state.isFullscreen and currentLayout ~= "mono" and count > 1 then
        screenGap = config.borderWidth
    end

    local workArea = {
        x = area.x + screenGap,
        y = area.y + screenGap,
        w = area.w - (screenGap * 2),
        h = area.h - (screenGap * 2)
    }

    local function setFrameSmart(win, newFrame)
        if not newFrame or newFrame.w <= 0 or newFrame.h <= 0 then
            return
        end

        local id = win:id()
        if state.windowState[id] then
            state.windowState[id].isHidden = false
        end

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

    -- Fullscreen mode
    if state.isFullscreen and not isSpecial then
        for _, win in ipairs(windows) do
            setFrameSmart(win, { x = area.x, y = area.y, w = area.w, h = area.h })
        end
        return
    end

    -- Mono (formerly monocle)
    if currentLayout == "mono" then
        for _, win in ipairs(windows) do
            setFrameSmart(win, {
                x = workArea.x,
                y = workArea.y,
                w = workArea.w,
                h = workArea.h,
            })
        end
        return
    end

    -- Scrolling (Niri-style horizontal ribbon)
    if currentLayout == "scrolling" then
        -- For scrolling, we use creation order for stability
        local windowsInOrder = core.getWindowsInCreationOrder(tag, allWins)
        if #windowsInOrder == 0 then return end

        local focused = hs.window.focusedWindow()
        local focusedId = focused and focused:id()
        local lastFocusedId = state.tagLastFocused[tag]

        local targetIdx = 1
        for i, win in ipairs(windowsInOrder) do
            local wid = win:id()
            if wid == focusedId then
                targetIdx = i
                break
            elseif wid == lastFocusedId then
                targetIdx = i
            end
        end

        -- Calculate total width of windows to the left of targetIdx
        local leftWidth = 0
        for i = 1, targetIdx - 1 do
            local winWidthRatio = state.windowWidths[windowsInOrder[i]:id()] or 0.7
            leftWidth = leftWidth + (workArea.w * winWidthRatio) + innerGap
        end

        -- Center the target window
        local targetWinWidthRatio = state.windowWidths[windowsInOrder[targetIdx]:id()] or 0.7
        local targetWinWidth = workArea.w * targetWinWidthRatio
        local targetX = workArea.x + (workArea.w - targetWinWidth) / 2

        -- Starting X for the very first window
        local currentX = targetX - leftWidth

        for _, win in ipairs(windowsInOrder) do
            local winWidthRatio = state.windowWidths[win:id()] or 0.7
            local winWidth = workArea.w * winWidthRatio
            setFrameSmart(win, {
                x = currentX,
                y = workArea.y,
                w = winWidth,
                h = workArea.h,
            })
            currentX = currentX + winWidth + innerGap
        end
        return
    end

    -- Tiling layouts (Vertical/Horizontal)
    local masterWin = windows[1]
    if count == 1 then
        setFrameSmart(masterWin, {
            x = workArea.x,
            y = workArea.y,
            w = workArea.w,
            h = workArea.h,
        })
    elseif currentLayout == "horizontal" then
        local masterHeight = state.getMasterWidth(tag) -- Reusing masterWidth for height in horizontal
        local availH = workArea.h - innerGap
        local mh = math.floor(availH * masterHeight)

        setFrameSmart(masterWin, {
            x = workArea.x,
            y = workArea.y,
            w = workArea.w,
            h = mh,
        })

        local sy = workArea.y + mh + innerGap
        local sh = availH - mh

        local stackWindows = count - 1
        local stackTotalWidth = workArea.w - ((stackWindows - 1) * innerGap)
        local sw = math.floor(stackTotalWidth / stackWindows)

        for i = 2, count do
            local stackIndex = i - 2
            local xPos = workArea.x + (stackIndex * (sw + innerGap))
            local wSize = sw

            if i == count then
                wSize = (workArea.x + workArea.w) - xPos
            end

            setFrameSmart(windows[i], {
                x = xPos,
                y = sy,
                w = wSize,
                h = sh,
            })
        end
    else -- Default to Vertical (formerly tile)
        local masterWidth = state.getMasterWidth(tag)
        local availW = workArea.w - innerGap
        local mw = math.floor(availW * masterWidth)

        setFrameSmart(masterWin, {
            x = workArea.x,
            y = workArea.y,
            w = mw,
            h = workArea.h,
        })

        local sx = workArea.x + mw + innerGap
        local sw = availW - mw

        local stackWindows = count - 1
        local stackTotalHeight = workArea.h - ((stackWindows - 1) * innerGap)
        local sh = math.floor(stackTotalHeight / stackWindows)

        for i = 2, count do
            local stackIndex = i - 2
            local yPos = workArea.y + (stackIndex * (sh + innerGap))
            local hSize = sh

            if i == count then
                hSize = (workArea.y + workArea.h) - yPos
            end

            setFrameSmart(windows[i], {
                x = sx,
                y = yPos,
                w = sw,
                h = hSize,
            })
        end
    end
end

-- =============================================================================
-- Manual Resize Handler
-- =============================================================================

function M.handleManualResize()
    local tag = state.special.active and state.special.tag or state.currentTag
    local currentLayout = state.getLayout(tag)

    if state.isFullscreen or currentLayout == "mono" then
        return
    end

    if state.isTagFree(tag) then
        return
    end

    local windows = core.getTiledWindows(tag)
    if #windows == 0 then
        return
    end

    local screen = hs.screen.mainScreen():frame()

    if currentLayout == "scrolling" then
        local focused = hs.window.focusedWindow()
        if not focused or core.isFloating(focused) then return end

        local f = focused:frame()
        local newWidthRatio = f.w / screen.w
        newWidthRatio = math.max(0.1, math.min(1.0, newWidthRatio))

        local currentRatio = state.windowWidths[focused:id()] or 0.7
        if math.abs(newWidthRatio - currentRatio) > 0.02 then
            state.windowWidths[focused:id()] = newWidthRatio
            state.triggerSave()
        end
        return
    end

    if #windows < 2 then return end
    local masterWin = windows[1]
    local masterFrame = masterWin:frame()

    if currentLayout == "horizontal" then
        if math.abs(masterFrame.h - screen.h) < 10 then
            return
        end

        local newMasterHeight = masterFrame.h / screen.h
        newMasterHeight = math.max(0.1, math.min(0.9, newMasterHeight))

        local currentHeight = state.getMasterWidth(tag)
        if math.abs(newMasterHeight - currentHeight) > 0.02 then
            state.setMasterWidth(tag, newMasterHeight)
        end
    else -- vertical
        if math.abs(masterFrame.w - screen.w) < 10 then
            return
        end

        local newMasterWidth = masterFrame.w / screen.w
        newMasterWidth = math.max(0.1, math.min(0.9, newMasterWidth))

        local currentWidth = state.getMasterWidth(tag)
        if math.abs(newMasterWidth - currentWidth) > 0.02 then
            state.setMasterWidth(tag, newMasterWidth)
        end
    end

    M.tile()
end

return M
