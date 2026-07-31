-- =============================================================================
-- NanoWM Layout Engine
-- Tiling logic, window positioning, and layout management
-- =============================================================================

local config = require("nanowm.config")
local state = require("nanowm.state")
local core = require("nanowm.core")
local profiler = require("nanowm.profiler")

local M = {}

-- Forward declarations for integration callbacks
M.onTileComplete = nil -- Set by integrations module

-- Where hidden windows are parked. macOS clamps this to ~40 px of on-screen visibility, so the
-- resulting frame is NOT this value — never test against it to decide if a window is parked;
-- use core.isParked() instead.
local PARK_COORD = 100000

-- =============================================================================
-- Debounced Tile Timer
-- =============================================================================

-- Build from the live power profile, not a hardcoded battery constant.
-- onPowerChange() only rebuilds this timer on an actual AC<->battery transition, so a
-- machine that boots on AC and stays plugged in would otherwise keep the slower battery
-- delay for the entire session.
local tileTimer = hs.timer.delayed.new(state.perfProfile().tileDelay, function()
    profiler.wrap("performTile", function() M.performTile() end)()
end)

function M.rebuildTileTimer()
    tileTimer:stop()
    tileTimer = hs.timer.delayed.new(state.perfProfile().tileDelay, function()
        profiler.wrap("performTile", function() M.performTile() end)()
    end)
end

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
                if not core.isParked(win, id) then win:raise() end
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

    -- Set of tags visible right now. core.classifyWindow() adds the special tag itself when
    -- special mode is active, so it does not need to be injected here.
    local visibleTags = {}
    for _, tag in ipairs(state.activeTags) do
        visibleTags[tag] = true
    end

    for _, win in ipairs(require("nanowm.watchers").getManagedWindows()) do
        local isVisible, isFloat = core.classifyWindow(win, visibleTags)
        if isVisible and isFloat and not core.isParked(win) then
            table.insert(floatingWins, win)
        end
    end

    for _, win in ipairs(floatingWins) do
        win:raise()
    end

    if state.special.active then
        for _, win in ipairs(core.getTiledWindows(state.special.tag)) do
            if not core.isParked(win) then
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

    local allWins = require("nanowm.watchers").getManagedWindows()
    require("nanowm.watchers").augmentAllWins(allWins)
    local toHide = {}
    local toFloat = {}

    local visibleTags = {}
    local screens = hs.screen.allScreens()
    local screenCount = #screens
    local primaryScreen = screens[1]
    local primaryFrame = primaryScreen and primaryScreen:frame() or {x=0,y=0,w=1920,h=1080}

    if state.sketchybarEnabled and primaryScreen then
        local name = primaryScreen:name()
        if name ~= "Built-in Retina Display" and name ~= "Color LCD" then
            primaryFrame.y = primaryFrame.y + config.sketchybarHeight
            primaryFrame.h = primaryFrame.h - config.sketchybarHeight
        end
    end

    -- Determine which tags should be visible on which screen frame
    for _, tag in ipairs(state.activeTags) do
        local targetScreen = state.getScreenForTag(tag)
        if targetScreen then
            local f = targetScreen:frame()
            if state.sketchybarEnabled then
                local name = targetScreen:name()
                if name ~= "Built-in Retina Display" and name ~= "Color LCD" then
                    f.y = f.y + config.sketchybarHeight
                    f.h = f.h - config.sketchybarHeight
                end
            end
            -- If multiple tags map to same screen (e.g. 1 screen setup), 
            -- prioritize the global currentTag or the one that appears first in activeTags
            if not visibleTags[tag] then
                -- Check if another tag already occupies this screen's space
                local screenOccupied = false
                for _, existingFrame in pairs(visibleTags) do
                    if existingFrame.x == f.x and existingFrame.y == f.y then
                        screenOccupied = true; break
                    end
                end

                -- Special logic: if it's the global currentTag, it MUST be visible
                if tag == state.currentTag or not screenOccupied then
                    -- If it's the currentTag, it kicks out whatever was on that screen
                    if tag == state.currentTag then
                        for t2, f2 in pairs(visibleTags) do
                            if f2.x == f.x and f2.y == f.y then visibleTags[t2] = nil end
                        end
                    end
                    visibleTags[tag] = f
                end
            end
        end
    end

    if state.special.active then
        visibleTags[state.special.tag] = primaryFrame
    end
    -- PHASE 1: CLASSIFICATION
    for _, win in ipairs(allWins) do
        local id = win:id()
        if not state.tags[id] then
            core.registerWindow(win)
        end

        -- Classified via core so this and raiseFloating() cannot drift apart.
        local isVisible, isFloat = core.classifyWindow(win, visibleTags)

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
        if state.windowState[id] and state.windowState[id].isHidden then
            -- already parked off-screen; skip all AX calls
        else
            local idStr = tostring(id)
            local f = win:frame()

            -- No coordinate test for "already parked": reaching this branch means
            -- windowState.isHidden was false, which is the authority. The old `f.x < 90000`
            -- guard could never fail anyway (macOS clamps parked windows to ~screenWidth-40).
            if f.w > 0 and f.h > 0 then
                -- Remember where a floating window really was so PHASE 4 can restore its size.
                -- Previously gated on `f.x < 10000`, which a clamped parked position (1472)
                -- also satisfied — so a re-park could overwrite the cache with the parked
                -- position and the float would come back jammed against the screen edge.
                if core.isFloating(win) then
                    state.floatingCache[idStr] = { x = f.x, y = f.y, w = f.w, h = f.h }
                end

                f.x = PARK_COORD
                f.y = PARK_COORD
                win:setFrame(f)
            end
        end
        state.windowState[id] = state.windowState[id] or {}
        state.windowState[id].isHidden = true
    end

    -- PHASE 3: TILE BACKGROUND
    for tag, frame in pairs(visibleTags) do
        if tag ~= state.special.tag then
            local backgroundWindows = core.getTiledWindows(tag, allWins)
            if not state.isTagFree(tag) then
                M.applyLayout(backgroundWindows, frame, false, tag, allWins)
            else
                for _, win in ipairs(backgroundWindows) do
                    local id = win:id()
                    if state.windowState[id] and state.windowState[id].isHidden then
                        local cached = state.freeTagPositions[tag] and state.freeTagPositions[tag][id]
                        if cached then
                            win:setFrame(cached)
                        else
                            win:setFrame({
                                x = frame.x + (frame.w - frame.w*0.7)/2,
                                y = frame.y + (frame.h - frame.h*0.7)/2,
                                w = frame.w*0.7, h = frame.h*0.7
                            })
                        end
                        state.windowState[id].isHidden = false
                    end
                end
            end
        end
    end

    -- PHASE 3.5: TILE SPECIAL TAG
    if state.special.active then
        local frame = visibleTags[state.special.tag]
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
                        win:setFrame({
                            x = frame.x + (frame.w - frame.w*0.7)/2,
                            y = frame.y + (frame.h - frame.h*0.7)/2,
                            w = frame.w*0.7, h = frame.h*0.7
                        })
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
        local shouldRaise = state.windowState[id].isHidden or (state.lastIntendedFocusId == id) or onSpecial

        if shouldRaise then
            if state.windowState[id].isHidden then
                local saved = state.floatingCache[idStr]
                local winTag = state.tags[id]
                local targetFrame = visibleTags[winTag] or primaryFrame

                -- Only w/h are used below; saved.x/y are not a position source. The old
                -- `saved.x < 10000` validity test is redundant now that a parked position can
                -- no longer be written into the cache.
                if saved and saved.w > 0 and saved.h > 0 then
                    win:setFrame({
                        x = targetFrame.x + (targetFrame.w - saved.w) / 2,
                        y = targetFrame.y + (targetFrame.h - saved.h) / 2,
                        w = saved.w,
                        h = saved.h
                    })
                else
                    local w, h = targetFrame.w * 0.7, targetFrame.h * 0.7
                    win:setFrame({
                        x = targetFrame.x + (targetFrame.w - w) / 2,
                        y = targetFrame.y + (targetFrame.h - h) / 2,
                        w = w,
                        h = h
                    })
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
