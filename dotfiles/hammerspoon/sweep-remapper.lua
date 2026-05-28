-- =============================================================================
-- Aurora Sweep Browser Remapper (Right Control -> Command)
-- =============================================================================
-- This script replaces Karabiner-Elements for the Sweep.
-- It ensures browser shortcuts work without breaking ZMK mouse reports.
-- Specifically targets Right Control (Keycode 62).
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

-- Create the event tap
-- We listen for keyDown, keyUp, and flagsChanged events.
_G.sweepBrowserTap = hs.eventtap.new({
    hs.eventtap.event.types.keyDown,
    hs.eventtap.event.types.keyUp,
    hs.eventtap.event.types.flagsChanged
}, function(event)
    -- 1. Check if the active app is a browser
    local app = hs.application.frontmostApplication()
    if not app or not BROWSER_BUNDLES[app:bundleID()] then
        return false
    end

    -- 2. Verify it is exactly the Right Control key
    -- This ensures Left Control on your internal keyboard remains standard.
    if event:getKeyCode() ~= RIGHT_CTRL then
        return false
    end

    -- 3. Perform the Flag Swap
    -- We add CMD and remove CTRL.
    -- This makes RCTRL+T act as CMD+T in browsers.
    local flags = event:getFlags()
    local newFlags = {}
    for k, v in pairs(flags) do newFlags[k] = v end
    newFlags.cmd = true
    newFlags.ctrl = false

    event:setFlags(newFlags)

    -- Return false to let the modified event pass through
    return false
end)

-- Start the tap
_G.sweepBrowserTap:start()
log.i("Right-Control Browser Remapper Active")
