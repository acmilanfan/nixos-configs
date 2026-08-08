-- =============================================================================
-- NanoWM Tag Management
-- Tag navigation, urgent tags, special tag, and free mode
-- =============================================================================

local config = require("nanowm.config")
local state = require("nanowm.state")
local core = require("nanowm.core")
local layout = require("nanowm.layout")

local M = {}

-- Forward declarations for integration callbacks
M.onTagChange = nil -- Set by integrations module

-- =============================================================================
-- Special Tag Border
-- =============================================================================

local function updateBorder()
    if state.special.active then
        if not state.special.border then
            local screen = hs.screen.mainScreen():frame()
            state.special.border = hs.canvas.new(screen)
            state.special.border:level(hs.canvas.windowLevels.overlay)
            state.special.border[1] = {
                type = "rectangle",
                action = "stroke",
                strokeColor = { red = 0.2, green = 0.6, blue = 1.0, alpha = 0.8 },
                strokeWidth = 8,
                frame = { x = 4, y = 4, w = screen.w - 8, h = screen.h - 8 },
            }
        end
        state.special.border:show()
    else
        if state.special.border then
            state.special.border:hide()
        end
    end
end

M.updateBorder = updateBorder

-- =============================================================================
-- Urgent Tag Functions
-- =============================================================================

function M.markTagUrgent(tag)
    if tag == state.currentTag then
        return
    end
    if tag == state.special.tag and state.special.active then
        return
    end

    if not state.urgentTags[tag] then
        state.urgentTags[tag] = true
        if M.onTagChange then
            M.onTagChange()
        end
    end
end

function M.clearUrgent(tag)
    if state.urgentTags[tag] then
        state.urgentTags[tag] = nil
        if M.onTagChange then
            M.onTagChange()
        end
    end
end

function M.gotoUrgent()
    for tag, _ in pairs(state.urgentTags) do
        if tag == "special" then
            M.toggleSpecial()
        else
            M.gotoTag(tag)
        end
        return
    end
    hs.alert.show("No urgent tags")
end

function M.hasUrgentTags()
    return next(state.urgentTags) ~= nil
end

-- =============================================================================
-- Free Mode Functions
-- =============================================================================

function M.toggleFreeMode()
    local tag = state.special.active and state.special.tag or state.currentTag

    if state.freeTags[tag] then
        state.freeTags[tag] = nil
        state.freeTagPositions[tag] = nil
        hs.alert.show("Free Mode: OFF (Tag " .. tostring(tag) .. ")")
        layout.tile()
    else
        local windows = core.getTiledWindows(tag)
        state.freeTagPositions[tag] = {}
        for _, win in ipairs(windows) do
            local id = win:id()
            local f = win:frame()
            state.freeTagPositions[tag][id] = { x = f.x, y = f.y, w = f.w, h = f.h }
        end
        state.freeTags[tag] = true
        hs.alert.show("Free Mode: ON (Tag " .. tostring(tag) .. ")")
    end

    state.triggerSave()
    if M.onTagChange then
        M.onTagChange()
    end
end

-- =============================================================================
-- Snapshot Capture
-- =============================================================================

function M.captureSnapshot(tag)
    tag = tag or (state.special.active and state.special.tag or state.currentTag)

    local wins = core.getTiledWindows(tag)
    if #wins == 0 then
        state.tagSnapshots[tag] = nil
        return
    end

    -- Defer the blocking screen capture off the main thread critical path
    hs.timer.doAfter(0, function()
        local screen = hs.screen.mainScreen()
        if not screen then return end
        local snapshot = screen:snapshot()
        if snapshot then
            state.tagSnapshots[tag] = snapshot
        end
    end)
end

-- =============================================================================
-- Tag Navigation
-- =============================================================================

function M.focusNextMonitor()
    local screens = hs.screen.allScreens()
    if #screens <= 1 then return end

    local focusedWin = hs.window.focusedWindow()
    local currentScreen = focusedWin and focusedWin:screen() or hs.screen.mainScreen()
    local nextScreen = screens[1]

    for i, s in ipairs(screens) do
        if s == currentScreen then
            nextScreen = screens[i + 1] or screens[1]
            break
        end
    end

    local monitorIdx = 1
    for i, s in ipairs(screens) do
        if s == nextScreen then monitorIdx = i break end
    end

    local targetTag = state.activeTags[monitorIdx]
    M.gotoTag(targetTag)
end

function M.moveWindowToNextMonitor(win)
    win = win or hs.window.focusedWindow()
    if not win then return end

    local screens = hs.screen.allScreens()
    if #screens <= 1 then return end

    local currentScreen = win:screen()
    local nextScreen = screens[1]

    for i, s in ipairs(screens) do
        if s == currentScreen then
            nextScreen = screens[i + 1] or screens[1]
            break
        end
    end

    local monitorIdx = 1
    for i, s in ipairs(screens) do
        if s == nextScreen then monitorIdx = i break end
    end

    local targetTag = state.activeTags[monitorIdx]
    M.moveWindowToTag(targetTag, win)
end

function M.gotoTag(i)
    local numTag = tonumber(i)
    local monitorIdx = 1
    if numTag then
        monitorIdx = math.floor((numTag - 1) / 10) + 1
    end

    if i == state.currentTag and i == state.activeTags[monitorIdx] and not state.special.active then
        return
    end

    M.captureSnapshot()

    -- Save current tag state just in case
    state.tagFullscreenState[state.currentTag] = state.isFullscreen

    -- Save focused window
    local focusedWin = hs.window.focusedWindow()
    if focusedWin and state.tags[focusedWin:id()] == state.currentTag then
        state.tagLastFocused[state.currentTag] = focusedWin:id()
    end

    state.prevTag = state.currentTag
    state.currentTag = i
    state.activeTags[monitorIdx] = i
    state.special.active = false

    -- Restore new tag state
    state.isFullscreen = state.tagFullscreenState[i] or false

    state.lastManualTagSwitch = hs.timer.secondsSinceEpoch()
    M.clearUrgent(i)

    state.triggerSave()
    updateBorder()

    if M.onTagChange then
        M.onTagChange()
    end

    layout.tile()

    local wins = core.getTiledWindows(i)
    local lastFocusedId = state.tagLastFocused[i]

    -- Check if the last focused was a floating window on this tag
    local floatTarget = nil
    if lastFocusedId then
        local w = hs.window(lastFocusedId)
        if w and state.tags[lastFocusedId] == i and core.isFloating(w) then
            floatTarget = w
        end
    end

    if floatTarget then
        hs.timer.doAfter(0.15, function() floatTarget:focus() end)
    elseif #wins > 0 then
        hs.timer.doAfter(0.15, function()
            local targetWin = nil
            if lastFocusedId then
                for _, w in ipairs(wins) do
                    if w:id() == lastFocusedId then
                        targetWin = w
                        break
                    end
                end
            end
            if targetWin then
                targetWin:focus()
            else
                wins[1]:focus()
            end
        end)
    else
        -- If tag is empty, focus preferred app to ensure no old window stays frontmost
        hs.timer.doAfter(0.15, function()
            if config.emptyTagFocusApp then
                local app = hs.application.get(config.emptyTagFocusApp)
                if app then
                    -- Only activate if it already has windows to avoid opening new ones
                    local appWins = app:allWindows()
                    if #appWins > 0 then
                        app:activate()
                    end
                else
                    -- If app isn't running, don't force launch it
                end
            end
        end)
    end
end

function M.togglePrevTag()
    M.gotoTag(state.prevTag)
end

-- =============================================================================
-- Special Tag
-- =============================================================================

function M.toggleSpecial()
    -- Save state of the current context before switching
    local oldContextTag = state.special.active and state.special.tag or state.currentTag
    state.tagFullscreenState[oldContextTag] = state.isFullscreen

    -- Save focused window
    local focusedWin = hs.window.focusedWindow()
    if focusedWin and state.tags[focusedWin:id()] == oldContextTag then
        state.tagLastFocused[oldContextTag] = focusedWin:id()
    end

    M.captureSnapshot()

    state.special.active = not state.special.active

    -- Restore state of the new context
    local newContextTag = state.special.active and state.special.tag or state.currentTag
    state.isFullscreen = state.tagFullscreenState[newContextTag] or false

    state.lastManualTagSwitch = hs.timer.secondsSinceEpoch()

    if state.special.active then
        M.clearUrgent(state.special.tag)
    end

    updateBorder()
    layout.tile()

    if state.special.raiseTimer then
        state.special.raiseTimer:stop()
        state.special.raiseTimer = nil
    end

    local wins = core.getTiledWindows(newContextTag)
    if #wins > 0 then
        if state.special.active then
            for _, win in ipairs(wins) do
                win:raise()
            end
        end

        hs.timer.doAfter(0.15, function()
            local lastFocusedId = state.tagLastFocused[newContextTag]
            local targetWin = nil

            if lastFocusedId then
                for _, w in ipairs(wins) do
                    if w:id() == lastFocusedId then
                        targetWin = w
                        break
                    end
                end
            end

            if targetWin then
                targetWin:focus()
            else
                wins[1]:focus()
            end
        end)
    else
        -- If special tag is empty, focus preferred app to ensure no old window stays frontmost
        hs.timer.doAfter(0.15, function()
            if config.emptyTagFocusApp then
                local app = hs.application.get(config.emptyTagFocusApp)
                if app then
                    -- Only activate if it already has windows to avoid opening new ones
                    local appWins = app:allWindows()
                    if #appWins > 0 then
                        app:activate()
                    end
                end
            end
        end)
    end
end

-- =============================================================================
-- Move Window to Tag
-- =============================================================================

function M.moveWindowToTag(destTag, win)
    win = win or hs.window.focusedWindow()
    if not win then
        return
    end

    local id = win:id()
    local currentTag = state.tags[id]

    -- Capture position for proportional remapping when crossing screens
    local oldWf, oldScreen
    if currentTag and core.isFloating(win) then
        if state.windowState[id] and state.windowState[id].isHidden then
            local cached = state.floatingCache[tostring(id)]
            if cached and cached.w and cached.h then
                -- Reject parked positions (macOS clamps to ~40px of bottom-right corner)
                local cs = state.getScreenForTag(currentTag)
                if cs then
                    local sf = cs:frame()
                    if cached.x > sf.x + sf.w - 100 and cached.y > sf.y + sf.h - 100 then
                        -- Parked: keep w/h only, x/y will be centered later
                        cached = nil
                    end
                end
            end
            if cached then
                oldWf = cached
                oldScreen = state.getScreenForTag(currentTag)
            end
        else
            oldWf = win:frame()
            oldScreen = state.getScreenForTag(currentTag)
        end
    end

    -- Record move for undo (if not already there)
    if currentTag ~= destTag then
        state.lastMove = { winId = id, fromTag = currentTag, toTag = destTag }
    end

    if currentTag and state.stacks[currentTag] then
        for i, vid in ipairs(state.stacks[currentTag]) do
            if vid == id then
                table.remove(state.stacks[currentTag], i)
                break
            end
        end
    end

    state.tags[id] = destTag

    -- Always remove from the old tag's creation order, floating or not.
    if currentTag and state.tagCreationOrder[currentTag] then
        for i, vid in ipairs(state.tagCreationOrder[currentTag]) do
            if vid == id then
                table.remove(state.tagCreationOrder[currentTag], i)
                break
            end
        end
    end

    -- Only tiled windows belong in the stack and creation order. registerWindow() already
    -- skips both for floating windows; this path did not, so every floating window moved
    -- here left an id behind that never tiles. bringWindowToCurrentContext() sets
    -- floatingOverrides[id] before calling us, so Alt+Y / ORGINDEX / weekenduo all hit this.
    -- getTiledWindows() prunes such ids only for tags it actually tiles, so phantoms
    -- persisted on non-active tags and were saved to disk with the rest of the state.
    if not core.isFloating(win) then
        if not state.stacks[destTag] then
            state.stacks[destTag] = {}
        end
        table.insert(state.stacks[destTag], 1, id)

        if not state.tagCreationOrder[destTag] then
            state.tagCreationOrder[destTag] = {}
        end
        table.insert(state.tagCreationOrder[destTag], id)
    end

    if currentTag then
        core.resetMasterWidthIfNeeded(currentTag)
    end

    state.triggerSave()
    layout.tile()

    -- Remap position proportionally when crossing screens, and prevent
    -- PHASE 4 from re-centering floating windows moved to another tag.
    if oldWf and oldScreen then
        local targetScreen = state.getScreenForTag(destTag)
        if targetScreen and oldScreen ~= targetScreen then
            local of = oldScreen:frame()
            local sf = targetScreen:frame()
            local rx = (oldWf.x - of.x) / of.w
            local ry = (oldWf.y - of.y) / of.h
            local newX = sf.x + rx * sf.w
            local newY = sf.y + ry * sf.h
            local newWf = { x = newX, y = newY, w = oldWf.w, h = oldWf.h }
            win:setFrame(newWf)
        elseif targetScreen then
            win:setFrame(oldWf)
        end
        if state.windowState[id] and state.windowState[id].isHidden then
            local wf = win:frame()
            state.floatingCache[tostring(id)] = { x = wf.x, y = wf.y, w = wf.w, h = wf.h }
        end
    end

    -- Focus management: Always handle if moving into view or away from view
    local activeTag = state.special.active and state.special.tag or state.currentTag
    state.lastIntendedFocusId = id

    hs.timer.doAfter(0.15, function()
        if destTag == activeTag then
            -- Window moved INTO our view: ensure it's frontmost
            win:focus()
            -- Extra raise AFTER focus to defeat macOS app-stacking
            hs.timer.doAfter(0.01, function() win:raise() end)
        elseif currentTag == activeTag and destTag ~= activeTag then
            -- The window left our view, so something else has to take focus.
            --
            -- This used to be `core.getTiledWindows(currentTag)[1]` — the head of the tag's
            -- stack. Under mono or fullscreen every tiled window occupies the same rectangle,
            -- so the stack head bears no relation to what is actually visible, and focus
            -- appeared to jump to a random window. It also ignored floating windows entirely.
            --
            -- Pick by real z-order instead: orderedWindows() is front-to-back, so the first
            -- match is the window now revealed underneath. This also naturally prefers a
            -- remaining floating window, since floats sit on top.
            local successor = nil
            local watchers = require("nanowm.watchers")
            if not (watchers.axBlocked and watchers.axBlocked()) then
                for _, w in ipairs(hs.window.orderedWindows()) do
                    local wid = w:id()
                    if wid and wid ~= id
                        and (state.tags[wid] == currentTag or state.sticky[wid]) then
                        successor = w
                        break
                    end
                end
            end
            -- Fallbacks: last window focused on this tag, then the old stack-head behaviour.
            if not successor then
                local lastId = state.tagLastFocused[currentTag]
                if lastId and lastId ~= id then
                    for _, w in ipairs(core.getAllVisibleWindows()) do
                        if w:id() == lastId then successor = w break end
                    end
                end
            end
            if not successor then
                successor = core.getTiledWindows(currentTag)[1]
            end

            if successor then
                state.lastIntendedFocusId = successor:id()
                successor:focus()
                -- Keep floating windows above the newly focused window. macOS raises the
                -- focused window's app to the front, which otherwise buries every other
                -- floating window on this tag behind it — the reported "moving one floating
                -- window hides the others" symptom. layout.raiseFloating() does exactly this
                -- and, until now, was never called from anywhere.
                layout.raiseFloating()
            elseif config.emptyTagFocusApp then
                local app = hs.application.get(config.emptyTagFocusApp)
                if app then
                    -- Only activate if it already has windows to avoid opening new ones
                    local appWins = app:allWindows()
                    if #appWins > 0 then
                        app:activate()
                    end
                end
            end
        end
    end)
end

function M.undoLastMove()
    if not state.lastMove then
        hs.alert.show("Nothing to undo")
        return
    end

    local id = state.lastMove.winId
    local fromTag = state.lastMove.fromTag
    local toTag = state.lastMove.toTag

    local win = hs.window(id)
    if not win then
        hs.alert.show("Window not found")
        state.lastMove = nil
        return
    end

    -- Reverse the move
    if state.tags[id] == toTag then
        -- Temporarily clear lastMove to avoid recursion or double recording if we use moveWindowToTag
        local lastMove = state.lastMove
        state.lastMove = nil

        -- Move it back
        if state.stacks[toTag] then
            for i, vid in ipairs(state.stacks[toTag]) do
                if vid == id then
                    table.remove(state.stacks[toTag], i)
                    break
                end
            end
        end

        if state.tagCreationOrder[toTag] then
            for i, vid in ipairs(state.tagCreationOrder[toTag]) do
                if vid == id then
                    table.remove(state.tagCreationOrder[toTag], i)
                    break
                end
            end
        end

        state.tags[id] = fromTag
        if not state.stacks[fromTag] then
            state.stacks[fromTag] = {}
        end
        table.insert(state.stacks[fromTag], 1, id)

        if not state.tagCreationOrder[fromTag] then
            state.tagCreationOrder[fromTag] = {}
        end
        table.insert(state.tagCreationOrder[fromTag], id)

        core.resetMasterWidthIfNeeded(toTag)
        state.triggerSave()
        layout.tile()

        hs.alert.show("Undo: Moved back to Tag " .. tostring(fromTag))
    else
        hs.alert.show("Window state changed, cannot undo")
        state.lastMove = nil
    end
end

-- =============================================================================
-- Tag Memory Functions
-- =============================================================================

function M.saveCurrentWindowTag()
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
    if config.excludedFromTagMemory[appName] then
        hs.alert.show(appName .. " is excluded from tag memory")
        return
    end

    local key = state.getWindowKey(win)
    if not key then
        hs.alert.show("Window has no valid title to save")
        return
    end

    local tag = state.tags[win:id()]
    if not tag then
        hs.alert.show("Window has no tag")
        return
    end

    state.appTagMemory[key] = tag
    state.triggerSave()
    hs.alert.show("Saved: " .. string.sub(key, 1, 30) .. "... -> Tag " .. tostring(tag))
end

function M.saveAllWindowTags()
    local saved = 0
    local skipped = 0

    for _, win in ipairs(require("nanowm.watchers").getManagedWindows()) do
        local app = win:application()
        if app then
            local appName = app:name()
            if not config.excludedFromTagMemory[appName] then
                local key = state.getWindowKey(win)
                if key then
                    local tag = state.tags[win:id()]
                    if tag then
                        state.appTagMemory[key] = tag
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

    state.triggerSave()
    hs.alert.show("Saved " .. saved .. " window tags (skipped " .. skipped .. ")")
end

return M
