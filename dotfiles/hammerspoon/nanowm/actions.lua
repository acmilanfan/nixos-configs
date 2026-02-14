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
            win:setFrame(hs.screen.mainScreen():frame())
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

-- =============================================================================
-- Focus Cycling
-- =============================================================================

function M.cycleFocus(dir)
    local allVisible

    if state.special.active then
        allVisible = core.getTiledWindows(state.special.tag)
        for _, win in ipairs(hs.window.filter.default:getWindows()) do
            local id = win:id()
            if state.tags[id] == state.special.tag and core.isFloating(win) then
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
        allVisible = core.getAllVisibleWindows()
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
        win:centerOnScreen()
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
    if not win or not core.isFloating(win) then
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
    state.layout = (state.layout == "tile") and "monocle" or "tile"
    layout.tile()
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
