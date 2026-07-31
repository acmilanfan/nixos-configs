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
        -- Remember the floating size, unless the window is parked (in which case the frame is
        -- the clamped parked one, not a size worth restoring).
        if f.w > 0 and f.h > 0 and not core.isParked(win, id) then
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
-- Picture-in-Picture Focus
-- =============================================================================

-- Browsers that can host a PiP window, for the scoped fallback below.
local PIP_HOSTS = { "Firefox", "Google Chrome", "Safari", "Brave", "Arc" }

local function isPipTitle(title)
    return title == "Picture-in-Picture" or title == "Picture in Picture"
end

function M.focusPip()
    local watchers = require("nanowm.watchers")

    local function grab(win)
        win:focus()
        win:raise()
        hs.alert.show("Focused PiP", 0.5)
    end

    -- 1. Tracked windows first: getManagedWindows() iterates _trackedWins and performs no
    -- AX enumeration. PiP windows reach _trackedWins via the windowCreated/windowFocused
    -- handlers, which (unlike the resync paths) don't require isStandard().
    for _, win in ipairs(watchers.getManagedWindows()) do
        if isPipTitle(win:title()) then
            grab(win)
            return
        end
    end

    -- 2. Fallback: one runningApplications() pass filtered to the PiP hosts. Never
    -- hs.window.allWindows() — the old global enumeration cost 44-66 ms and ran straight off
    -- a hotkey with no guard, so it could freeze the event loop on keypress under an AX lock.
    --
    -- Deliberately NOT hs.application.get(name) per browser: for an app that is not running
    -- that call costs ~50 ms (measured), because it falls back to a bundle-ID/Launch Services
    -- lookup. A five-name loop with four absent browsers measured 211 ms — slower than the
    -- global call it was meant to replace. One runningApplications() pass is ~11 ms.
    if watchers.axBlocked() then
        hs.alert.show("PiP: AX busy, try again", 1)
        return
    end
    local hosts = {}
    for _, n in ipairs(PIP_HOSTS) do hosts[n] = true end
    for _, app in ipairs(hs.application.runningApplications()) do
        if hosts[app:name() or ""] then
            for _, win in ipairs(app:allWindows()) do
                if isPipTitle(win:title()) then
                    grab(win)
                    return
                end
            end
        end
    end

    hs.alert.show("No PiP window found", 0.5)
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
        if core.isParked(win) then
            -- Window is parked off-screen: pull it back to a sane frame instead of nudging the
            -- clamped one. This branch was previously unreachable (`f.x >= 90000` never held).
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
    local title = win:title()
    local isPip = (title == "Picture-in-Picture" or title == "Picture in Picture")
    local delta = 0.05
    local aspect = frame.w / frame.h

    if direction == "wider" then
        local oldW = frame.w
        frame.w = frame.w * (1 + delta)
        if isPip then
            frame.h = frame.w / aspect
            -- For PiP, enlarging from center often fails; try resizing from bottom-left anchor
            frame.y = frame.y - (frame.h - (oldW / aspect))
        else
            frame.x = frame.x - (frame.w - oldW) / 2
        end
    elseif direction == "narrower" then
        local oldW = frame.w
        frame.w = math.max(frame.w * (1 - delta), 200)
        if isPip then
            frame.h = frame.w / aspect
            frame.y = frame.y + ((oldW / aspect) - frame.h)
        else
            frame.x = frame.x + (oldW - frame.w) / 2
        end
    elseif direction == "taller" then
        local oldH = frame.h
        frame.h = frame.h * (1 + delta)
        if isPip then
            frame.w = frame.h * aspect
            frame.x = frame.x - (frame.w - (oldH * aspect))
        else
            frame.y = frame.y - (frame.h - oldH) / 2
        end
    elseif direction == "shorter" then
        local oldH = frame.h
        frame.h = math.max(frame.h * (1 - delta), 200)
        if isPip then
            frame.w = frame.h * aspect
            frame.x = frame.x + ((oldH * aspect) - frame.w)
        else
            frame.y = frame.y + (oldH - frame.h) / 2
        end
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
    local step = 50

    if direction == "left" then
        frame.x = frame.x - step
    elseif direction == "right" then
        frame.x = frame.x + step
    elseif direction == "up" then
        frame.y = frame.y - step
    elseif direction == "down" then
        frame.y = frame.y + step
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
