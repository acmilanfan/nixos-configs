-- =============================================================================
-- NanoWM Window Actions
-- Float, sticky, fullscreen, resize, move, and other window operations
-- =============================================================================

local config = require("nanowm.config")
local state = require("nanowm.state")
local core = require("nanowm.core")
local layout = require("nanowm.layout")

local M = {}

-- =============================================================================
-- Toggle Float
-- =============================================================================

function M.toggleFloat()
    local win = hs.window.focusedWindow()
    if not win then
        return
    end

    local id = win:id()
    local idStr = tostring(id)
    local currentlyFloating = core.isFloating(win)

    state.floatingOverrides[id] = not currentlyFloating
    local tag = state.tags[id]

    if currentlyFloating then
        -- Float -> Tile
        local f = win:frame()
        if f.x < 10000 then
            state.sizeCache[idStr] = { w = f.w, h = f.h }
        end
        if not state.stacks[tag] then
            state.stacks[tag] = {}
        end
        table.insert(state.stacks[tag], 1, id)

        -- Also add to creation order so scrolling layout includes this window
        if not state.tagCreationOrder[tag] then
            state.tagCreationOrder[tag] = {}
        end
        local foundInOrder = false
        for _, existingId in ipairs(state.tagCreationOrder[tag]) do
            if existingId == id then foundInOrder = true; break end
        end
        if not foundInOrder then
            table.insert(state.tagCreationOrder[tag], id)
        end
    else
        -- Tile -> Float
        if state.stacks[tag] then
            for i, vid in ipairs(state.stacks[tag]) do
                if vid == id then
                    table.remove(state.stacks[tag], i)
                    break
                end
            end
        end

        local saved = state.sizeCache[idStr]
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

    state.triggerSave()
    layout.tile()
end

-- =============================================================================
-- Toggle Sticky
-- =============================================================================

function M.toggleSticky()
    local win = hs.window.focusedWindow()
    if not win then
        return
    end

    local id = win:id()
    if state.sticky[id] then
        state.sticky[id] = nil
    else
        state.sticky[id] = true
        win:raise()
    end

    state.triggerSave()
    layout.tile()
end

-- =============================================================================
-- Toggle Fullscreen
-- =============================================================================

function M.toggleFullscreen()
    local win = hs.window.focusedWindow()
    if not win then
        return
    end

    local idStr = tostring(win:id())

    if core.isFloating(win) then
        if state.fullscreenCache[idStr] then
            win:setFrame(state.fullscreenCache[idStr])
            state.fullscreenCache[idStr] = nil
        else
            local f = win:frame()
            state.fullscreenCache[idStr] = { x = f.x, y = f.y, w = f.w, h = f.h }
            local frame = hs.screen.mainScreen():frame()
            if state.sketchybarEnabled then
                local name = hs.screen.mainScreen():name()
                if name ~= "Built-in Retina Display" and name ~= "Color LCD" then
                    frame.y = frame.y + config.sketchybarHeight
                    frame.h = frame.h - config.sketchybarHeight
                end
            end
            win:setFrame(frame)
        end
        win:raise()
    else
        state.isFullscreen = not state.isFullscreen

        local currentContextTag = state.special.active and state.special.tag or state.currentTag
        state.tagFullscreenState[currentContextTag] = state.isFullscreen

        if state.isFullscreen then
            win:raise()
        end
        layout.tile()
    end

    state.triggerSave()
end

function M.bringWindowToCurrentContext(win, sizeFactor)
    if not win then return end
    local id = win:id()
    local targetTag = state.special.active and state.special.tag or state.currentTag

    -- Initialize state to prevent layout engine interference or "restoring" to old hidden position
    state.windowState[id] = state.windowState[id] or {}
    state.windowState[id].isHidden = false
    state.lastIntendedFocusId = id

    if sizeFactor then
        state.floatingOverrides[id] = true
    end

    -- Use the centralized move method
    local tags = require("nanowm.tags")
    tags.moveWindowToTag(targetTag, win)

    -- Handle sizing if floating
    if sizeFactor and core.isFloating(win) then
        local screen = hs.screen.mainScreen():frame()
        local newW = screen.w * sizeFactor
        local newH = screen.h * sizeFactor
        local newX = screen.x + (screen.w - newW) / 2
        local newY = screen.y + (screen.h - newH) / 2
        win:setFrame({ x = newX, y = newY, w = newW, h = newH })
    end

    -- Explicit raise to be extra safe
    win:raise()
end

-- =============================================================================
-- Focus Cycling
-- =============================================================================

function M.cycleFocus(dir)
    local focused = hs.window.focusedWindow()
    local allVisible = core.getAllVisibleWindows()

    if #allVisible == 0 then
        return
    end

    local idx = 0
    if focused then
        local fid = focused:id()
        for i, win in ipairs(allVisible) do
            if win:id() == fid then
                idx = i
                break
            end
        end
    end

    -- If not found, try the last intended focus ID (robustness against stale focus)
    if idx == 0 and state.lastIntendedFocusId then
        for i, win in ipairs(allVisible) do
            if win:id() == state.lastIntendedFocusId then
                idx = i
                break
            end
        end
    end

    if idx == 0 then
        -- Default to the first or last depending on direction
        if dir > 0 then
            idx = 0 -- idx + 1 will be 1
        else
            idx = #allVisible + 1 -- idx - 1 will be #allVisible
        end
    end

    local newIdx = idx + dir
    if newIdx < 1 then
        newIdx = #allVisible
    end
    if newIdx > #allVisible then
        newIdx = 1
    end

    local targetWin = allVisible[newIdx]
    state.lastIntendedFocusId = targetWin:id()
    targetWin:focus()

    if core.isFloating(targetWin) then
        targetWin:raise()
    end
end

-- =============================================================================
-- Window Swapping
-- =============================================================================

function M.swapWindow(dir)
    local tag = state.special.active and state.special.tag or state.currentTag
    local stack = state.stacks[tag]

    if not stack or #stack < 2 then
        return
    end

    local focused = hs.window.focusedWindow()
    if not focused then
        return
    end

    if core.isFloating(focused) then
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

    -- Also swap in creation order if it exists
    local order = state.tagCreationOrder[tag]
    if order then
        local oIdx = 0

        for i, id in ipairs(order) do
            if id == fid then oIdx = i end
        end

        if oIdx > 0 then
            local nextOIdx = oIdx + dir
            if nextOIdx < 1 then nextOIdx = #order end
            if nextOIdx > #order then nextOIdx = 1 end
            order[oIdx], order[nextOIdx] = order[nextOIdx], order[oIdx]
        end
    end

    state.triggerSave()
    layout.tile()

    hs.timer.doAfter(0.01, function()
        focused:focus()
    end)
end

-- =============================================================================
-- Center Window
-- =============================================================================

function M.centerWindow()
    local win = hs.window.focusedWindow()
    if win then
        local f = win:frame()
        if f.x >= 90000 then
            -- Window is hidden, pull it back first
            local screen = win:screen():frame()
            local w, h = screen.w * 0.7, screen.h * 0.7
            local x = screen.x + (screen.w - w) / 2
            local y = screen.y + (screen.h - h) / 2
            win:setFrame({ x = x, y = y, w = w, h = h })
        else
            win:centerOnScreen()
        end
        win:raise()
    end
end

-- =============================================================================
-- Floating Window Operations
-- =============================================================================

function M.resizeFloatingTo60()
    local win = hs.window.focusedWindow()
    if not win or not core.isFloating(win) then
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

function M.resizeFloatingWindow(direction)
    local win = hs.window.focusedWindow()
    if not win or not core.isFloating(win) then return end

    local frame = win:frame()
    local screen = win:screen():frame()
    local delta = 0.05

    if direction == "wider" then
        local oldW = frame.w
        frame.w = math.min(frame.w * (1 + delta), screen.w)
        frame.x = frame.x - (frame.w - oldW) / 2
    elseif direction == "narrower" then
        local oldW = frame.w
        frame.w = math.max(frame.w * (1 - delta), 200)
        frame.x = frame.x + (oldW - frame.w) / 2
    elseif direction == "taller" then
        local oldH = frame.h
        frame.h = math.min(frame.h * (1 + delta), screen.h)
        frame.y = frame.y - (frame.h - oldH) / 2
    elseif direction == "shorter" then
        local oldH = frame.h
        frame.h = math.max(frame.h * (1 - delta), 200)
        frame.y = frame.y + (oldH - frame.h) / 2
    end

    win:setFrame(frame)
end

function M.adjustTiledSize(direction)
    local win = hs.window.focusedWindow()
    if not win or core.isFloating(win) then return end

    local tag = state.special.active and state.special.tag or state.currentTag
    local currentLayout = state.getLayout(tag)

    if currentLayout == "scrolling" then
        local id = win:id()
        local currentRatio = state.windowWidths[id] or 0.7
        if direction == "wider" then
            state.windowWidths[id] = math.min(1.0, currentRatio + 0.05)
        elseif direction == "narrower" then
            state.windowWidths[id] = math.max(0.1, currentRatio - 0.05)
        end
        state.triggerSave()
        layout.tile()
    else
        -- Vertical/Horizontal master resizing
        local currentMasterWidth = state.getMasterWidth(tag)
        if direction == "wider" or direction == "taller" then
            state.setMasterWidth(tag, math.min(0.9, currentMasterWidth + 0.05))
        elseif direction == "narrower" or direction == "shorter" then
            state.setMasterWidth(tag, math.max(0.1, currentMasterWidth - 0.05))
        end
        layout.tile()
    end
end

function M.cycleWindowSize()
    local win = hs.window.focusedWindow()
    if not win or core.isFloating(win) then return end

    local tag = state.special.active and state.special.tag or state.currentTag
    local currentLayout = state.getLayout(tag)

    if currentLayout == "scrolling" then
        local id = win:id()
        local currentRatio = state.windowWidths[id] or 0.7
        local sizes = { 0.5, 0.7, 1.0 }
        local nextRatio = sizes[1]

        for i, s in ipairs(sizes) do
            if math.abs(currentRatio - s) < 0.01 then
                nextRatio = sizes[i + 1] or sizes[1]
                break
            end
        end

        state.windowWidths[id] = nextRatio
        state.triggerSave()
        layout.tile()
        hs.alert.show("Window Width: " .. math.floor(nextRatio * 100) .. "%")
    end
end

function M.moveFloatingWindow(direction)
    local win = hs.window.focusedWindow()
    if not win or not core.isFloating(win) then
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

-- =============================================================================
-- Close Window
-- =============================================================================

function M.closeWindow()
    local win = hs.window.focusedWindow()
    if win then
        win:close()
    end
end

-- =============================================================================
-- Toggle Gaps
-- =============================================================================

function M.toggleGaps()
    state.gap = (state.gap == 0) and 4 or 0
    layout.tile()
    hs.alert.show("Gaps: " .. (state.gap == 0 and "OFF" or "ON"))
end

-- =============================================================================
-- Toggle Layout
-- =============================================================================

function M.toggleLayout()
    local tag = state.special.active and state.special.tag or state.currentTag
    local currentLayout = state.getLayout(tag)
    local nextLayout = state.availableLayouts[1]

    for i, layoutName in ipairs(state.availableLayouts) do
        if layoutName == currentLayout then
            nextLayout = state.availableLayouts[i + 1] or state.availableLayouts[1]
            break
        end
    end

    state.setLayout(tag, nextLayout)
    layout.tile()
    hs.alert.show("Layout: " .. nextLayout:upper())
end

-- =============================================================================
-- Toggle Caffeinate
-- =============================================================================

function M.toggleCaffeinate()
    state.caffeinateActive = not state.caffeinateActive
    hs.caffeinate.set("displayIdle", state.caffeinateActive, true)

    local status = state.caffeinateActive and "on" or "off"
    hs.alert.show("Caffeinate: " .. status:upper())

    hs.task.new("/bin/zsh", nil, { "-c", "sketchybar --trigger nanowm_caffeinate STATE=" .. status }):start()
end

return M
