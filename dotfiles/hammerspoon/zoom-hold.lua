-- =============================================================================
-- Hold Control+Option to zoom (macOS Zoom), release to zoom out
--
-- macOS's own "modifiers for temporary actions: toggle zoom" reacts to the modifiers
-- alone, so every Ctrl+Alt hotkey (tags 11-20, window moves, ...) zoomed the screen too.
-- It is disabled in darwin/common.nix (AX_ZOOM_TEMP_TOGGLE) and replaced by this: zoom
-- only when Control+Option are held with no other key for HOLD seconds. Pressing any
-- key (or adding a modifier) during the hold makes it a shortcut instead, and undoes a
-- zoom that already started. Zoom is toggled with macOS's ⌥⌘8 shortcut, enabled via
-- closeViewHotkeysEnabled in darwin/common.nix.
-- =============================================================================

local HOLD = 0.45  -- long enough not to fire between the modifiers and the key of a chord

local types = hs.eventtap.event.types
local props = hs.eventtap.event.properties
local MARK = 0x5A4F4F4D  -- "ZOOM": tags our own synthetic key events so the tap ignores them
local KEY_8 = hs.keycodes.map["8"]

local holdTimer = nil
local zoomed = false

local function toggleZoom()
    for _, down in ipairs({ true, false }) do
        local e = hs.eventtap.event.newKeyEvent({ "alt", "cmd" }, KEY_8, down)
        e:setProperty(props.eventSourceUserData, MARK)
        e:post()
    end
end

local function stopHold()
    if holdTimer then holdTimer:stop(); holdTimer = nil end
    if zoomed then
        zoomed = false
        toggleZoom()
    end
end

-- Held in _G: an unreferenced eventtap is garbage-collected and silently stops.
if _G.zoomHoldTap then _G.zoomHoldTap:stop() end
_G.zoomHoldTap = hs.eventtap.new({ types.flagsChanged, types.keyDown }, function(e)
    if e:getProperty(props.eventSourceUserData) == MARK then return false end

    if e:getType() == types.keyDown then
        -- A key during the hold: this is a Ctrl+Alt shortcut, not a zoom.
        if holdTimer or zoomed then stopHold() end
        return false
    end

    local f = e:getFlags()
    local onlyCtrlAlt = f.ctrl and f.alt and not f.cmd and not f.shift and not f.fn
    if onlyCtrlAlt then
        if not holdTimer and not zoomed then
            holdTimer = hs.timer.doAfter(HOLD, function()
                holdTimer = nil
                zoomed = true
                toggleZoom()
            end)
        end
    else
        stopHold()  -- released, or another modifier joined
    end
    return false
end):start()
