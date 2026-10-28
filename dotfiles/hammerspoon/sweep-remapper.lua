-- =============================================================================
-- Browser Remapper (Right Control <-> Right Command)
-- =============================================================================
-- Stateful version: Ensures modifiers are swapped for the entire chord.
-- Started for the Aurora Sweep (whose right thumb has Ctrl); the right Cmd -> Ctrl
-- half gives the laptop's home-row mods a right-hand Ctrl in browsers.
-- =============================================================================

local log = hs.logger.new('SweepRemapper', 'info')

-- Target Browsers
local BROWSER_BUNDLES = {
    ["org.mozilla.firefox"] = true,
    ["com.apple.Safari"] = true,
    ["com.google.Chrome"] = true
}

-- macOS Keycodes
local RIGHT_CTRL = 62
local RIGHT_CMD = 54
-- Device-specific modifier bits (hs.eventtap.event.rawFlagMasks)
local masks = hs.eventtap.event.rawFlagMasks
local DEV_LEFT_CTRL = masks.deviceLeftControl     -- 0x1
local DEV_RIGHT_CTRL = masks.deviceRightControl   -- 0x2000
local DEV_LEFT_CMD = masks.deviceLeftCommand      -- 0x8
local DEV_RIGHT_CMD = masks.deviceRightCommand    -- 0x10

-- State tracking
local rCtrlActive = false
local rCmdActive = false

-- Cache the frontmost app's bundle ID so the event tap doesn't call the
-- Accessibility API on every keyDown/keyUp/flagsChanged event.
local _frontBundleID = nil
if _G.sweepAppWatcher then _G.sweepAppWatcher:stop() end
_G.sweepAppWatcher = hs.application.watcher.new(function(_, event, app)
    if event == hs.application.watcher.activated then
        _frontBundleID = app and app:bundleID()
    end
end)
_G.sweepAppWatcher:start()
local _seedApp = hs.application.frontmostApplication()
_frontBundleID = _seedApp and _seedApp:bundleID()

-- Whether the RIGHT key of a modifier is held after this event. This used the combined
-- flag, which stays set while the LEFT key is held: hold left, tap right, release right,
-- and the left key kept acting as the swapped modifier. Use the device-specific bit when
-- the event carries left/right bits; otherwise (some virtual keyboards don't set them)
-- each right-key event flips the state. Either way a full release of the modifier resets it.
local function rightHeld(active, event, keyCode, flag, rightKey, devLeft, devRight)
    if not event:getFlags()[flag] then return false end
    if keyCode ~= rightKey or event:getType() ~= hs.eventtap.event.types.flagsChanged then
        return active
    end
    local raw = event:rawFlags()
    if raw & (devLeft | devRight) ~= 0 then return raw & devRight ~= 0 end
    return not active
end

_G.sweepBrowserTap = hs.eventtap.new({
    hs.eventtap.event.types.keyDown,
    hs.eventtap.event.types.keyUp,
    hs.eventtap.event.types.flagsChanged
}, function(event)
    local keyCode = event:getKeyCode()

    -- 1. Browser Check (cache lookup — no AX call per keypress)
    if not BROWSER_BUNDLES[_frontBundleID] then
        -- Reset state if we leave the browser
        rCtrlActive = false
        rCmdActive = false
        return false
    end

    -- 2. Update Right-Control / Right-Command State
    rCtrlActive = rightHeld(rCtrlActive, event, keyCode, "ctrl", RIGHT_CTRL, DEV_LEFT_CTRL, DEV_RIGHT_CTRL)
    rCmdActive = rightHeld(rCmdActive, event, keyCode, "cmd", RIGHT_CMD, DEV_LEFT_CMD, DEV_RIGHT_CMD)

    -- 3. Perform the Swap
    -- Right Ctrl acts as Cmd and right Cmd as Ctrl; the left keys keep their meaning.
    if rCtrlActive or rCmdActive then
        local flags = event:getFlags()
        local raw = event:rawFlags()
        local leftCtrl = raw & DEV_LEFT_CTRL ~= 0 or (flags.ctrl and not rCtrlActive)
        local leftCmd = raw & DEV_LEFT_CMD ~= 0 or (flags.cmd and not rCmdActive)
        local newFlags = {}
        for k, v in pairs(flags) do newFlags[k] = v end
        newFlags.ctrl = (leftCtrl or rCmdActive) or nil
        newFlags.cmd = (leftCmd or rCtrlActive) or nil
        event:setFlags(newFlags)
    end

    return false
end)

_G.sweepBrowserTap:start()
log.i("Browser right Ctrl <-> Cmd swap (Stateful) Active")
