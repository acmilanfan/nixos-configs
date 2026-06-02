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
    -- We track if the RIGHT control specifically is being held.
    if keyCode == RIGHT_CTRL then
        rCtrlActive = flags.ctrl
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
