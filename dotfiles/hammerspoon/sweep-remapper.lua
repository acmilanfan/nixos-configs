-- =============================================================================
-- Aurora Sweep Browser Remapper (Control -> Command)
-- =============================================================================
-- This script replaces Karabiner-Elements for the Sweep.
-- It ensures browser shortcuts work without breaking ZMK mouse reports.
-- =============================================================================

local log = hs.logger.new('SweepRemapper', 'info')

-- Target Browsers
local BROWSER_BUNDLES = {
    ["org.mozilla.firefox"] = true,
    ["com.apple.Safari"] = true,
    ["com.google.Chrome"] = true
}

-- Create the event tap
-- We listen for keyDown, keyUp, and flagsChanged events.
-- We apply the remapping to ALL keyboards when in a browser to avoid
-- the 'keyboardEventDeviceId' error on flagsChanged events.
_G.sweepBrowserTap = hs.eventtap.new({
    hs.eventtap.event.types.keyDown,
    hs.eventtap.event.types.keyUp,
    hs.eventtap.event.types.flagsChanged
}, function(event)
    -- 1. Check if any Control key is involved
    local flags = event:getFlags()
    if not flags.ctrl then return false end

    -- 2. Check if the active app is a browser
    local app = hs.application.frontmostApplication()
    if not app or not BROWSER_BUNDLES[app:bundleID()] then
        return false
    end

    -- 3. Perform the Flag Swap
    -- We add CMD and remove CTRL.
    -- This makes CTRL+T act as CMD+T in browsers.
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
log.i("Universal Browser Remapper Active (Stable)")
