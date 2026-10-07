-- =============================================================================
-- Aurora Sweep Browser Remapper (Right Control -> Command)
-- =============================================================================
-- Stateful version: Ensures modifiers are swapped for the entire chord.
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
-- Device-specific modifier bits (hs.eventtap.event.rawFlagMasks)
local DEV_LEFT_CTRL = hs.eventtap.event.rawFlagMasks.deviceLeftControl    -- 0x1
local DEV_RIGHT_CTRL = hs.eventtap.event.rawFlagMasks.deviceRightControl  -- 0x2000

-- State tracking
local rCtrlActive = false

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

_G.sweepBrowserTap = hs.eventtap.new({
    hs.eventtap.event.types.keyDown,
    hs.eventtap.event.types.keyUp,
    hs.eventtap.event.types.flagsChanged
}, function(event)
    local keyCode = event:getKeyCode()
    local flags = event:getFlags()

    -- 1. Browser Check (cache lookup — no AX call per keypress)
    if not BROWSER_BUNDLES[_frontBundleID] then
        rCtrlActive = false -- Reset state if we leave the browser
        return false
    end

    -- 2. Update Right-Control State
    -- We track if the RIGHT control specifically is being held. This used `flags.ctrl`, the
    -- combined flag, which stays set while LEFT control is held: hold left, tap right, release
    -- right, and left control kept acting as Cmd. Use the device-specific bit when the event
    -- carries left/right bits; otherwise (some virtual keyboards don't set them) each right-ctrl
    -- event flips the state. Either way a full control release resets it.
    if keyCode == RIGHT_CTRL and event:getType() == hs.eventtap.event.types.flagsChanged then
        local raw = event:rawFlags()
        if not flags.ctrl then
            rCtrlActive = false
        elseif raw & (DEV_LEFT_CTRL | DEV_RIGHT_CTRL) ~= 0 then
            rCtrlActive = raw & DEV_RIGHT_CTRL ~= 0
        else
            rCtrlActive = not rCtrlActive
        end
    elseif not flags.ctrl then
        rCtrlActive = false
    end

    -- 3. Perform the Swap
    -- If RCTRL is active (or this IS the RCTRL key event), swap flags.
    if rCtrlActive and flags.ctrl then
        local newFlags = {}
        for k, v in pairs(flags) do newFlags[k] = v end
        newFlags.cmd = true
        newFlags.ctrl = false
        event:setFlags(newFlags)
    end

    return false
end)

_G.sweepBrowserTap:start()
log.i("Aurora Sweep RCTRL -> CMD (Stateful) Active")
