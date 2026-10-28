-- =============================================================================
-- Firefox Tab Mode
-- =============================================================================
-- Ctrl+Z in Firefox expands the vertical tab strip (Firefox's own sidebar
-- toggle) and enters a mode where j/k or Down/Up switch to the next/previous
-- tab. Enter, Esc or Ctrl+Z collapse the strip again and leave the mode, as do
-- any other key, a mouse click and switching to another app (the key or click
-- still goes through), so j/k never stay captured by accident.
--
-- Firefox can't move keyboard focus into the tab strip on its own (that needs
-- chrome JS, i.e. patching Firefox.app), so the mode switches tabs with
-- Ctrl+Tab / Ctrl+Shift+Tab. Those go in strip order while
-- browser.ctrlTab.sortByRecentlyUsed is off (pinned in firefox.nix).
-- =============================================================================

local FIREFOX = "org.mozilla.firefox"
local types = hs.eventtap.event.types

-- Keystrokes are posted to Firefox's process directly, so they skip
-- Hammerspoon's own hotkeys (no recursion into the Ctrl+Z binding below).
local function send(mods, key)
    local app = hs.application.get(FIREFOX)
    if app then hs.eventtap.keyStroke(mods, key, 20000, app) end
end

local mode = hs.hotkey.modal.new()
local active = false

local function nextTab() send({ "ctrl" }, "tab") end
local function prevTab() send({ "ctrl", "shift" }, "tab") end
local function leave()
    if not active then return end  -- several events can queue a leave
    mode:exit()
    send({ "ctrl" }, "z")
end

for _, key in ipairs({ "j", "down" }) do mode:bind({}, key, nextTab, nil, nextTab) end
for _, key in ipairs({ "k", "up" }) do mode:bind({}, key, prevTab, nil, prevTab) end
for _, key in ipairs({ "return", "escape" }) do mode:bind({}, key, leave) end
mode:bind({ "ctrl" }, "z", leave)

-- Keys the mode itself handles or sends (tab, z); anything else ends the mode.
local modeKeys = {}
for _, key in ipairs({ "j", "k", "down", "up", "return", "escape", "z", "tab" }) do
    modeKeys[hs.keycodes.map[key]] = true
end

local otherInput = hs.eventtap.new({ types.keyDown, types.leftMouseDown, types.rightMouseDown }, function(e)
    if e:getType() == types.keyDown and modeKeys[e:getKeyCode()] then return false end
    hs.timer.doAfter(0, leave)
    return false
end)

function mode:entered() active = true; otherInput:start() end
function mode:exited() active = false; otherInput:stop() end

local trigger = hs.hotkey.new({ "ctrl" }, "z", function()
    send({ "ctrl" }, "z")
    mode:enter()
end)

-- Only claim Ctrl+Z (and the mode keys) while Firefox is frontmost.
local function sync(bundleID)
    if bundleID == FIREFOX then
        trigger:enable()
    else
        mode:exit()
        trigger:disable()
    end
end

if _G.firefoxTabModeWatcher then _G.firefoxTabModeWatcher:stop() end
_G.firefoxTabModeWatcher = hs.application.watcher.new(function(_, event, app)
    if event == hs.application.watcher.activated then
        sync(app and app:bundleID())
    end
end)
_G.firefoxTabModeWatcher:start()
local front = hs.application.frontmostApplication()
sync(front and front:bundleID())
