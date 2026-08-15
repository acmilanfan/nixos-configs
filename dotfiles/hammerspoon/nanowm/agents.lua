-- =============================================================================
-- NanoWM AI Agents Module
-- Detect Claude Code / Gemini CLI sessions and focus their terminals.
-- =============================================================================

local M = {}

-- Terminal app names (ucomm) we know how to focus
local TERMINALS = {
    alacritty = true, Alacritty = true,
    kitty = true,
    WezTerm = true, wezterm = true,
    ["iTerm2"] = true,
    Terminal = true,
    Hyper = true,
}

-- =============================================================================
-- Process helpers
-- =============================================================================

-- Parse `ps -eo pid,ppid,ucomm` output. Pure: the caller supplies the text, so the subprocess
-- can be run asynchronously. The blocking exec()/sh() helpers this module used to carry are
-- gone — nothing here touches the main thread with a subprocess any more.
local function parseProcessTable(psOut)
    local procs = {}
    for line in (psOut or ""):gmatch("[^\n]+") do
        local pid, ppid, comm = line:match("^%s*(%d+)%s+(%d+)%s+(%S+)")
        if pid then procs[pid] = { ppid = ppid, ucomm = comm } end
    end
    return procs
end

local function findTerminalPid(pid, procs)
    local cur = tostring(pid)
    for _ = 1, 15 do
        if not cur or cur == "1" then return nil end
        local info = procs[cur]
        if not info then return nil end
        if TERMINALS[info.ucomm] then return tonumber(cur) end
        cur = info.ppid
    end
    return nil
end

local function focusWindowOnTag(win)
    local state = require("nanowm.state")
    local tags  = require("nanowm.tags")

    local tag = state.tags[win:id()]
    if tag and tag ~= state.currentTag then
        if tag == "special" then
            if not state.special.active then
                tags.toggleSpecial()
            end
        else
            tags.gotoTag(tag)
        end
    end
    hs.timer.doAfter(0.05, function()
        win:focus()
    end)
end

local function focusByPid(termPid)
    local app = hs.application.applicationForPID(termPid)
    if app then
        local win = app:focusedWindow() or app:mainWindow()
        if win then
            focusWindowOnTag(win)
        else
            app:activate(true)
        end
    end
end

-- =============================================================================
-- NOTE: M.getAgents() and M.getStatus() lived here -- ~150 lines of synchronous agent
-- detection built on blocking hs.execute() calls. They had zero callers anywhere: the
-- sketchybar plugins and the tmux hooks in nixos/home-manager/common/tmux.nix only use
-- focusAgent() and onAgentStateChange(), and the chooser uses the async zsh script in
-- showMenu(). Deleting them also removed a second, drifting copy of the confirm-prompt /
-- tty / cpu heuristics that had to be kept in sync with that script by hand.
-- =============================================================================

-- =============================================================================
-- Focus agent terminal
-- =============================================================================

function M.focusAgent(paneId)
    -- All the tmux work happens in ONE shell invocation, which prints the controlling client's
    -- pid. This used to be four blocking calls -- three of them `zsh -lc`, i.e. full login
    -- shells that source the entire profile -- run directly on the Hammerspoon main thread.
    --
    -- It matters more than an ordinary hotkey path: the sketchybar agent-focus plugin invokes
    -- this via `hs -c`, and blocking the event loop while an IPC request is in flight is what
    -- produced the `hs.ipc: already recursing` floods.
    --
    -- paneId is passed as an argument rather than interpolated, so no quoting or escaping.
    local script = [==[
        pane_target="$1"
        info=$(tmux list-panes -a -F '#{pane_id} #{session_name} #{window_index}' \
                    -f "#{m:#{pane_id},$pane_target}" 2>/dev/null)
        [ -z "$info" ] && exit 1
        # ${=info} forces word splitting: zsh, unlike sh/bash, does NOT split unquoted
        # expansions, so a plain `set -- $info` leaves $1 holding the whole line and $2/$3
        # empty — every tmux call below would then get an empty target.
        set -- ${=info}
        tmux switch-client -t "$2"    2>/dev/null
        tmux select-window -t "$2:$3" 2>/dev/null
        tmux select-pane   -t "$1"    2>/dev/null
        tmux list-clients  -t "$2" -F '#{client_pid}' 2>/dev/null | head -1
    ]==]

    hs.task.new("/bin/zsh", function(exitCode, stdOut)
        if exitCode ~= 0 then
            hs.alert.show("Could not locate tmux pane " .. tostring(paneId))
            return
        end
        local clientPid = (stdOut or ""):match("(%d+)")
        if not clientPid then return end

        -- Process table, also async. The terminal-detection walk stays in Lua so TERMINALS
        -- remains the single definition instead of being duplicated into shell -- the mistake
        -- that made the deleted getAgents() a maintenance burden.
        hs.task.new("/bin/ps", function(_, psOut)
            local termPid = findTerminalPid(clientPid, parseProcessTable(psOut))
            if termPid then focusByPid(termPid) end
        end, { "-eo", "pid,ppid,ucomm" }):start()
    end, { "-lc", script, "nanowm-focus-agent", tostring(paneId) }):start()
end

-- =============================================================================
-- Event-driven state change handler (called via hs IPC from tmux)
-- =============================================================================

-- Track per-agent last notified state to avoid duplicate alerts
local lastNotifiedState = {}

function M.onAgentStateChange(agentState, agentName)
    if not agentState or not agentName then return end

    -- Only notify once per state transition per agent
    if lastNotifiedState[agentName] == agentState then return end
    lastNotifiedState[agentName] = agentState

    local label = agentName:sub(1,1):upper() .. agentName:sub(2)

    if agentState == "needs-input" then
        hs.alert.show(label .. " needs input", 3)
    elseif agentState == "done" then
        hs.alert.show(label .. " finished", 3)
    elseif agentState == "off" then
        -- Clean up tracking for exited agents
        lastNotifiedState[agentName] = nil
    end
end

-- =============================================================================
-- NanoWM chooser menu
-- =============================================================================

local STATUS_ICON  = { working = "● ", confirm = "⚠ ", recent = "◉ ", idle = "○ " }
local STATUS_LABEL = { working = "working", confirm = "needs input", recent = "waiting", idle = "idle" }

local chooser = nil

-- Map agent-indicator states to display states
local STATUS_MAP = {
    ["needs-input"] = "confirm",
    running = "working",
    done = "recent",
    idle = "idle",
}

function M.showMenu()
    if chooser then chooser:delete() end
    chooser = hs.chooser.new(function(choice)
        if not choice then return end
        if choice.uuid and choice.uuid ~= "loading" then
            M.focusAgent(choice.paneId)
        end
    end)
    chooser:width(55)
    chooser:bgDark(true)
    chooser:fgColor({ hex = "#FFFFFF" })
    chooser:subTextColor({ hex = "#CCCCCC" })
    chooser:placeholderText("Focus AI agent…")
    chooser:searchSubText(true)
    chooser:choices({{text = "Loading agents...", uuid = "loading"}})
    chooser:show()

    -- ai-agent-list is the shared detection script (Nix-installed via
    -- home.packages), also used by the sketchybar popup and the tmux fzf
    -- switcher. Using "-lc" (login shell) for consistency with
    -- M.focusAgent's zsh invocation above and as a safety margin against
    -- PATH resolution depending on profile sourcing in other environments.
    hs.task.new("/bin/zsh", function(exitCode, stdOut)
        if not chooser:isVisible() then return end

        local choices = {}
        for line in stdOut:gmatch("[^\n]+") do
            local paneId, status, typeName, project, cwd = line:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|(.*)$")
            if paneId then
                local s = STATUS_MAP[status] or "working"
                table.insert(choices, {
                    text    = STATUS_ICON[s] .. typeName .. ": " .. project,
                    subText = STATUS_LABEL[s] .. "  •  " .. cwd,
                    uuid    = paneId,
                    paneId  = paneId,
                })
            end
        end

        if #choices == 0 then
            chooser:choices({{text = "No AI agents running", uuid = "loading"}})
        else
            chooser:choices(choices)
        end
    end, {"-lc", "ai-agent-list"}):start()
end

return M
