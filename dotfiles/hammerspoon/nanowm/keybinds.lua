-- =============================================================================
-- NanoWM Key Bindings
-- All hotkey definitions in one place
-- =============================================================================

local config = require("nanowm.config")
local state = require("nanowm.state")
local core = require("nanowm.core")
local layout = require("nanowm.layout")
local actions = require("nanowm.actions")
local tags = require("nanowm.tags")
local menus = require("nanowm.menus")
local integrations = require("nanowm.integrations")
local agents = require("nanowm.agents")

local M = {}

-- Modifier shortcuts
local alt = config.modifiers.alt
local altShift = config.modifiers.altShift
local ctrlAlt = config.modifiers.ctrlAlt
local ctrlAltShift = config.modifiers.ctrlAltShift
local cmdAlt = config.modifiers.cmdAlt
local cmdAltShift = config.modifiers.cmdAltShift
local cmdAltShiftCtrl = config.modifiers.cmdAltShiftCtrl

-- =============================================================================
-- Setup Function
-- =============================================================================

function M.setup()
    -- =========================================================================
    -- MENUS
    -- =========================================================================
    hs.hotkey.bind(alt, "m", menus.triggerMenuPalette)
    hs.hotkey.bind(alt, "p", function() menus.openMenu("commands") end)
    hs.hotkey.bind(alt, "i", function() menus.openMenu("windows") end)
    hs.hotkey.bind(alt, "/", menus.showKeybindMenu)

    -- AI Agents: chooser (Alt+A) and SketchyBar popup toggle (Ctrl+Alt+A)
    hs.hotkey.bind(alt,     "a", agents.showMenu)
    hs.hotkey.bind(ctrlAlt, "a", function()
        hs.task.new("/bin/zsh", nil, { "-c", "sketchybar --set ai_agents popup.drawing=toggle 2>/dev/null" }):start()
    end)

    -- Forward Cmd+Shift+/ to app (Help menu)
    hs.hotkey.bind(altShift, "/", function()
        hs.eventtap.keyStroke({ "cmd", "shift" }, "/")
    end)

    -- =========================================================================
    -- NAVIGATION
    -- =========================================================================
    hs.hotkey.bind(alt, "j", function() actions.cycleFocus(1) end)
    hs.hotkey.bind(alt, "k", function() actions.cycleFocus(-1) end)

    hs.hotkey.bind(alt, "h", function()
        local tag = state.special.active and state.special.tag or state.currentTag
        local currentWidth = state.getMasterWidth(tag)
        state.setMasterWidth(tag, math.max(0.1, currentWidth - 0.05))
        layout.tile()
    end)

    hs.hotkey.bind(alt, "l", function()
        local tag = state.special.active and state.special.tag or state.currentTag
        local currentWidth = state.getMasterWidth(tag)
        state.setMasterWidth(tag, math.min(0.9, currentWidth + 0.05))
        layout.tile()
    end)

    -- =========================================================================
    -- TAGS
    -- =========================================================================
    for i = 1, 9 do
        hs.hotkey.bind(alt, tostring(i), function() tags.gotoTag(i) end)
        hs.hotkey.bind(altShift, tostring(i), function() tags.moveWindowToTag(i) end)
    end
    hs.hotkey.bind(alt, "0", function() tags.gotoTag(10) end)
    hs.hotkey.bind(altShift, "0", function() tags.moveWindowToTag(10) end)

    hs.hotkey.bind(alt, "escape", tags.togglePrevTag)
    hs.hotkey.bind(alt, "s", tags.toggleSpecial)
    hs.hotkey.bind(altShift, "s", function()
        tags.moveWindowToTag(state.special.tag)
        hs.alert.show("Moved to Special")
    end)
    hs.hotkey.bind(alt, "u", tags.gotoUrgent)

    -- Tag memory
    hs.hotkey.bind(altShift, "m", tags.saveCurrentWindowTag)
    hs.hotkey.bind(ctrlAltShift, "m", tags.saveAllWindowTags)

    -- =========================================================================
    -- WINDOW MANAGEMENT
    -- =========================================================================
    hs.hotkey.bind({ "cmd" }, "space", actions.toggleLayout)
    hs.hotkey.bind(alt, "f", actions.toggleFullscreen)
    hs.hotkey.bind(alt, "c", actions.centerWindow)
    hs.hotkey.bind(altShift, "c", actions.resizeFloatingTo60)
    hs.hotkey.bind(alt, "g", actions.toggleGaps)
    hs.hotkey.bind(ctrlAltShift, "s", actions.toggleSticky)
    hs.hotkey.bind(altShift, "space", actions.toggleFloat)
    hs.hotkey.bind(altShift, "q", actions.closeWindow)
    hs.hotkey.bind(ctrlAlt, "f", tags.toggleFreeMode)

    -- Combined swap/resize keybinds (context-aware)
    hs.hotkey.bind(altShift, "h", function()
        local win = hs.window.focusedWindow()
        if win and core.isFloating(win) then
            actions.resizeFloatingWindow("narrower")
        else
            actions.swapWindow(-1)
        end
    end)

    hs.hotkey.bind(altShift, "l", function()
        local win = hs.window.focusedWindow()
        if win and core.isFloating(win) then
            actions.resizeFloatingWindow("wider")
        else
            actions.swapWindow(1)
        end
    end)

    hs.hotkey.bind(altShift, "k", function()
        local win = hs.window.focusedWindow()
        if win and core.isFloating(win) then
            actions.resizeFloatingWindow("shorter")
        else
            actions.swapWindow(-1)
        end
    end)

    hs.hotkey.bind(altShift, "j", function()
        local win = hs.window.focusedWindow()
        if win and core.isFloating(win) then
            actions.resizeFloatingWindow("taller")
        else
            actions.swapWindow(1)
        end
    end)

    -- Floating window movement
    hs.hotkey.bind(ctrlAlt, "h", function() actions.moveFloatingWindow("left") end)
    hs.hotkey.bind(ctrlAlt, "l", function() actions.moveFloatingWindow("right") end)
    hs.hotkey.bind(ctrlAlt, "k", function() actions.moveFloatingWindow("up") end)
    hs.hotkey.bind(ctrlAlt, "j", function() actions.moveFloatingWindow("down") end)

    -- =========================================================================
    -- APPLICATIONS
    -- =========================================================================
    hs.hotkey.bind(alt, "return", function()
        core.launchTask("/usr/bin/open", { "-n", "-a", "Alacritty" })
    end)
    hs.hotkey.bind(altShift, "return", function()
        hs.application.launchOrFocus("Alacritty")
    end)
    hs.hotkey.bind(alt, "b", function()
        core.launchTask("/usr/bin/open", { "-n", "-a", "Firefox" })
    end)
    hs.hotkey.bind(altShift, "b", function()
        hs.application.launchOrFocus("Firefox")
    end)
    hs.hotkey.bind(alt, "d", function()
        hs.application.launchOrFocus("Raycast")
    end)
    hs.hotkey.bind(altShift, "v", function()
        hs.task.new("/usr/bin/open", nil, { "raycast://extensions/raycast/clipboard-history/clipboard-history" }):start()
    end)

    -- =========================================================================
    -- ORG MODE WINDOWS
    -- =========================================================================
    local function focusOrCreateOrgindex(titlePattern, launchCmd)
        local allWins = hs.window.allWindows()
        for _, win in ipairs(allWins) do
            local title = win:title() or ""
            if string.find(title, titlePattern, 1, true) then
                local id = win:id()
                local currentTag = state.tags[id]
                local targetTag = state.special.active and state.special.tag or state.currentTag

                if currentTag ~= targetTag then
                    if currentTag and state.stacks[currentTag] then
                        for i, vid in ipairs(state.stacks[currentTag]) do
                            if vid == id then
                                table.remove(state.stacks[currentTag], i)
                                break
                            end
                        end
                    end
                    state.tags[id] = targetTag
                    if not state.stacks[targetTag] then
                        state.stacks[targetTag] = {}
                    end
                    table.insert(state.stacks[targetTag], 1, id)
                    state.triggerSave()
                end

                win:raise()
                win:focus()
                layout.tile()
                return
            end
        end
        core.launchTask("/bin/zsh", { "-c", launchCmd })
    end

    hs.hotkey.bind(altShift, "o", function()
        focusOrCreateOrgindex(
            "ORGINDEX-AGENDA",
            '/Applications/Alacritty.app/Contents/MacOS/alacritty -o "window.dimensions.lines=20" -o "window.dimensions.columns=100" --title "ORGINDEX-AGENDA" -e zsh -c "nvim --cmd \\"cd ~/org/life\\" -c \\"lua require(\\\\\\"orgmode.api.agenda\\\\\\").agenda({span = 1})\\""'
        )
    end)

    hs.hotkey.bind(altShift, "w", function()
        focusOrCreateOrgindex(
            "ORGINDEX-WORK",
            '/Applications/Alacritty.app/Contents/MacOS/alacritty -o "window.dimensions.lines=20" -o "window.dimensions.columns=100" --title "ORGINDEX-WORK" -e zsh -c "cd ~/org/life && vim ~/org/life/work/work.org"'
        )
    end)

    hs.hotkey.bind(altShift, "d", function()
        focusOrCreateOrgindex(
            "ORGINDEX-DUMP",
            '/Applications/Alacritty.app/Contents/MacOS/alacritty -o "window.dimensions.lines=20" -o "window.dimensions.columns=100" --title "ORGINDEX-DUMP" -e zsh -c "cd ~/org/life && vim ~/org/life/dump.org"'
        )
    end)

    hs.hotkey.bind(altShift, "y", function()
        focusOrCreateOrgindex(
            "ORGINDEX-YOUTUBE",
            '/Applications/Alacritty.app/Contents/MacOS/alacritty -o "window.dimensions.lines=20" -o "window.dimensions.columns=100" --title "ORGINDEX-YOUTUBE" -e zsh -c "cd ~/org/consume && vim ~/org/consume/youtube/youtube1.org"'
        )
    end)

    -- =========================================================================
    -- TIMER MODAL
    -- =========================================================================
    local timerModal = hs.hotkey.modal.new(alt, "t")
    timerModal:bind("", "1", function() integrations.startTimer(5); timerModal:exit() end)
    timerModal:bind("", "2", function() integrations.startTimer(10); timerModal:exit() end)
    timerModal:bind("", "3", function() integrations.startTimer(60); timerModal:exit() end)
    timerModal:bind("", "4", function() integrations.startTimer(120); timerModal:exit() end)
    timerModal:bind("", "n", function() timerModal:exit(); integrations.startCustomTimer() end)
    timerModal:bind("", "r", function() integrations.showTimerRemaining(); timerModal:exit() end)
    timerModal:bind("", "c", function() integrations.cancelTimer(); timerModal:exit() end)
    timerModal:bind("", "escape", function() timerModal:exit() end)

    -- =========================================================================
    -- LEADER KEY MODAL
    -- =========================================================================
    local leader = hs.hotkey.modal.new(alt, ",")
    local leaderActive = false

    function leader:entered()
        hs.alert.show("Leader Mode Active", 999999)
        leaderActive = true
        tags.updateBorder()
    end

    function leader:exited()
        hs.alert.closeAll()
        leaderActive = false
        tags.updateBorder()
    end

    leader:bind("", "escape", function() leader:exit() end)
    leader:bind("", "l", function() hs.caffeinate.lockScreen(); leader:exit() end)
    leader:bind("", "k", function() integrations.toggleKanata(); leader:exit() end)
    leader:bind("", "t", function() core.launchTask("/usr/bin/open", { "-n", "-a", "Alacritty" }); leader:exit() end)
    leader:bind("", "b", function() core.launchTask("/usr/bin/open", { "-n", "-a", "Firefox" }); leader:exit() end)
    leader:bind("", "r", function() hs.reload(); leader:exit() end)
    leader:bind("", "q", function() leader:exit() end)

    -- =========================================================================
    -- INTEGRATIONS
    -- =========================================================================
    hs.hotkey.bind(altShift, "g", integrations.toggleSketchybar)
    hs.hotkey.bind(ctrlAlt, "b", integrations.toggleBorders)
    hs.hotkey.bind(ctrlAlt, "p", integrations.toggleBatterySaver)
    hs.hotkey.bind(ctrlAltShift, "k", menus.openKanataMenu)

    -- =========================================================================
    -- SYSTEM
    -- =========================================================================
    hs.hotkey.bind(ctrlAltShift, "r", function()
        hs.reload()
        hs.alert.show("NanoWM " .. config.VERSION .. " Reloaded")
    end)
    hs.hotkey.bind(ctrlAltShift, "c", hs.toggleConsole)
    hs.hotkey.bind(cmdAltShift, "c", actions.toggleCaffeinate)
    hs.hotkey.bind(cmdAltShiftCtrl, "l", function() hs.caffeinate.lockScreen() end)
end

return M
