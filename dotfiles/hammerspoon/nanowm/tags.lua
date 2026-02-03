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
M.onTagChange = nil  -- Set by integrations module

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
    if tag == state.currentTag then return end
    if tag == state.special.tag and state.special.active then return end

    if not state.urgentTags[tag] then
        state.urgentTags[tag] = true
        if M.onTagChange then M.onTagChange() end
    end
end

function M.clearUrgent(tag)
    if state.urgentTags[tag] then
        state.urgentTags[tag] = nil
        if M.onTagChange then M.onTagChange() end
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
    for _, _ in pairs(state.urgentTags) do
        return true
    end
    return false
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
    if M.onTagChange then M.onTagChange() end
end

-- =============================================================================
-- Tag Navigation
-- =============================================================================

function M.gotoTag(i)
    if i == state.currentTag and not state.special.active then
        return
    end

    state.isFullscreen = false
    state.prevTag = state.currentTag
    state.currentTag = i
    state.special.active = false

    state.lastManualTagSwitch = hs.timer.secondsSinceEpoch()
    M.clearUrgent(i)

    state.triggerSave()
    updateBorder()

    if M.onTagChange then M.onTagChange() end

    layout.tile()

    local wins = core.getTiledWindows(i)
    if #wins > 0 then
        hs.timer.doAfter(0.01, function()
            wins[1]:focus()
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
    state.special.active = not state.special.active
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

    if state.special.active then
        local wins = core.getTiledWindows(state.special.tag)
        if #wins > 0 then
            for _, win in ipairs(wins) do
                win:raise()
            end
            hs.timer.doAfter(0.01, function()
                wins[1]:focus()
            end)
        end
    else
        local wins = core.getTiledWindows(state.currentTag)
        if #wins > 0 then
            wins[1]:focus()
        end
    end
end

-- =============================================================================
-- Move Window to Tag
-- =============================================================================

function M.moveWindowToTag(destTag)
    local win = hs.window.focusedWindow()
    if not win then return end

    local id = win:id()
    local currentTag = state.tags[id]

    if currentTag and state.stacks[currentTag] then
        for i, vid in ipairs(state.stacks[currentTag]) do
            if vid == id then
                table.remove(state.stacks[currentTag], i)
                break
            end
        end
    end

    state.tags[id] = destTag

    if not state.stacks[destTag] then
        state.stacks[destTag] = {}
    end
    table.insert(state.stacks[destTag], 1, id)

    if currentTag then
        core.resetMasterWidthIfNeeded(currentTag)
    end

    state.triggerSave()
    layout.tile()
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

    for _, win in ipairs(hs.window.filter.default:getWindows()) do
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
