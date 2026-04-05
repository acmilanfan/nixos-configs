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

-- Direct execute for system-path tools (ps, lsof, awk, find).
local function exec(cmd)
    return (hs.execute(cmd)) or ""
end

-- Zsh login shell for nix-PATH tools (tmux, sketchybar).
local function sh(cmd)
    local escaped = cmd:gsub("'", "'\\''")
    return (hs.execute("/bin/zsh -lc '" .. escaped .. "'")) or ""
end

-- =============================================================================
-- Process helpers
-- =============================================================================

local function getProcessTable()
    local out = exec("ps -eo pid,ppid,ucomm")
    local procs = {}
    for line in out:gmatch("[^\n]+") do
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
-- Pane content helpers
-- =============================================================================

local function contentIsConfirm(content)
    if not content or content == "" then return false end
    if content:find("Allow once")
    or content:find("Allow for this session")
    or content:find("Allow in project")
    or content:find("Do you want to proceed?") then
        return true
    end

    -- Gemini numbered menu (require 2+ sequential numbered items in last 5 lines)
    local lineCount, numberedCount = 0, 0
    for _ in content:gmatch("[^\n]+") do lineCount = lineCount + 1 end
    local skip = lineCount > 5 and lineCount - 5 or 0
    local idx = 0
    for line in content:gmatch("[^\n]+") do
        idx = idx + 1
        if idx > skip and line:match("^%s*%d+%. ") then
            numberedCount = numberedCount + 1
        end
    end
    if numberedCount >= 2 then return true end

    -- TUI menu cursor (❯ or ›) followed by yes/no/deny
    local CURSOR  = "\xe2\x9d\xaf"
    local CURSOR2 = "\xe2\x80\xba"
    for line in content:gmatch("[^\n]+") do
        local s = line:match("^%s*(.-)%s*$")
        if s:sub(1,3) == CURSOR or s:sub(1,3) == CURSOR2 then
            local rest = s:sub(4):match("^%s*(.-)%s*$"):lower()
            if rest == "yes" or rest == "no" or rest == "deny" then
                return true
            end
        end
    end

    return content:find("[y/n]", 1, true) ~= nil or content:find("[Y/n]", 1, true) ~= nil
end

-- =============================================================================
-- Agent discovery
-- =============================================================================

function M.getAgents()
    local agents = {}

    -- Get global tmux environment variables (explicit states via hooks)
    local env = sh("tmux show-environment -g 2>/dev/null | grep '^TMUX_AGENT_PANE_'")

    -- Get all pane info to match CWD, PID, and TTY
    local panesOut = sh("tmux list-panes -a -F '#{pane_id}|#{pane_pid}|#{pane_tty}|#{pane_current_path}' 2>/dev/null")
    local panes = {}
    for line in panesOut:gmatch("[^\n]+") do
        local id, pid, tty, cwd = line:match("^([^|]+)|([^|]+)|([^|]+)|(.-)%s*$")
        if id then panes[id] = { pid = pid, tty = tty, cwd = cwd } end
    end

    local processedIds = {}

    -- 1. Explicit states from environment
    for id in env:gmatch("%%[0-9]+") do
        if not processedIds[id] then
            local escapedId = id:gsub("%%", "%%%%")
            local status = env:match("TMUX_AGENT_PANE_" .. escapedId .. "_STATE=([^%s\n]+)")
            local name   = env:match("TMUX_AGENT_PANE_" .. escapedId .. "_AGENT=([^%s\n]+)") or "Agent"

            if status and status ~= "off" then
                local info = panes[id]
                if info then
                    -- Verify process is still there
                    local ttyShort = info.tty:match("([^/]+)$")
                    if exec("ps -t " .. ttyShort .. " -o command= 2>/dev/null") ~= "" then
                        processedIds[id] = true

                        -- Check for confirm prompt override
                        local content = sh("tmux capture-pane -t '" .. id .. "' -p 2>/dev/null | tail -20")
                        if contentIsConfirm(content) then status = "needs-input" end

                        table.insert(agents, {
                            paneId  = id,
                            pid     = info.pid,
                            status  = status,
                            type    = name,
                            cwd     = info.cwd,
                            project = info.cwd:match("([^/]+)$") or "?",
                        })
                    else
                        -- Cleanup stale env
                        sh("tmux set-environment -ug TMUX_AGENT_PANE_" .. id .. "_STATE; tmux set-environment -ug TMUX_AGENT_PANE_" .. id .. "_AGENT")
                    end
                end
            end
        end
    end

    -- 2. Fallback: process detection (Gemini etc.)
    local AGENT_PROCESSES = { "claude", ".claude-wrapped", "gemini", "aider", "cursor" }
    for id, info in pairs(panes) do
        if not processedIds[id] then
            local ttyShort = info.tty:match("([^/]+)$")
            local psFull = exec("ps -t " .. ttyShort .. " -o command= 2>/dev/null")

            local foundAgent = nil
            for _, proc in ipairs(AGENT_PROCESSES) do
                if psFull:find(proc) then
                    foundAgent = proc; break
                end
            end

            if foundAgent then
                -- Use CPU as proxy for working vs idle
                local cpu = tonumber(exec("ps -t " .. ttyShort .. " -o %cpu= 2>/dev/null | awk '{s+=$1}END{print s}'")) or 0
                local status = (cpu > 1.0) and "running" or "idle"

                local content = sh("tmux capture-pane -t '" .. id .. "' -p 2>/dev/null | tail -20")
                if contentIsConfirm(content) then status = "needs-input" end

                table.insert(agents, {
                    paneId  = id,
                    pid     = info.pid,
                    status  = status,
                    type    = foundAgent,
                    cwd     = info.cwd,
                    project = info.cwd:match("([^/]+)$") or "?",
                })
            end
        end
    end

    return agents
end

-- =============================================================================
-- Status detection
-- =============================================================================

function M.getStatus(paneId)
    local status = sh("tmux show-environment -g 'TMUX_AGENT_PANE_" .. paneId .. "_STATE' 2>/dev/null | cut -d= -f2"):gsub("%s+$", "")

    local content = sh("tmux capture-pane -t '" .. paneId .. "' -p 2>/dev/null | tail -20")
    if contentIsConfirm(content) then return "confirm" end

    if status == "needs-input" then return "confirm"
    elseif status == "running" then return "working"
    elseif status == "done"    then return "recent"
    else
        -- Fallback detection status
        local panesOut = sh("tmux list-panes -a -F '#{pane_id}|#{pane_tty}' 2>/dev/null")
        local escapedId = paneId:gsub("%%", "%%%%")
        local tty = panesOut:match(escapedId .. "|([^%s\n]+)")
        if tty then
            local ttyShort = tty:match("([^/]+)$")
            local cpu = tonumber(exec("ps -t " .. ttyShort .. " -o %cpu= 2>/dev/null | awk '{s+=$1}END{print s}'")) or 0
            if cpu > 1.0 then return "working" else return "idle" end
        end
        return "working"
    end
end

-- =============================================================================
-- Focus agent terminal
-- =============================================================================

function M.focusAgent(paneId)
    local paneOut = sh("tmux list-panes -a -F '#{pane_id} #{session_name} #{window_index}' -f '#{m:#{pane_id}," .. paneId .. "}' 2>/dev/null")
    local pId, session, winIdx = paneOut:match("^(%%%d+) (%S+) (%d+)")

    if pId then
        sh(
            "tmux switch-client -t '" .. session .. "' 2>/dev/null; " ..
            "tmux select-window  -t '" .. session .. ":" .. winIdx .. "' 2>/dev/null; " ..
            "tmux select-pane    -t '" .. pId .. "' 2>/dev/null"
        )
        local clientOut = sh("tmux list-clients -t '" .. session .. "' -F '#{client_pid}' 2>/dev/null")
        local clientPid = clientOut:match("^(%d+)")

        if clientPid then
            local procs = getProcessTable()
            local termPid = findTerminalPid(clientPid, procs)
            if termPid then focusByPid(termPid) end
        end
    else
        hs.alert.show("Could not locate tmux pane " .. paneId)
    end
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

    -- Async execution
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
    end, {"-c", [=[
        agents=""

        # Explicit env
        env=$(tmux show-environment -g 2>/dev/null | grep '^TMUX_AGENT_PANE_')
        panes=$(tmux list-panes -a -F '#{pane_id}|#{pane_pid}|#{pane_tty}|#{pane_current_path}' 2>/dev/null)

        echo "$env" | while read -r line; do
            if [[ $line == TMUX_AGENT_PANE_*_STATE=* ]]; then
                id=$(echo "$line" | sed 's/TMUX_AGENT_PANE_\(.*\)_.*/\1/' | sed 's/_STATE.*//')
                state=$(echo "$line" | cut -d= -f2)

                if [[ "$state" != "off" ]]; then
                    name=$(echo "$env" | grep "TMUX_AGENT_PANE_${id}_AGENT" | cut -d= -f2)
                    [[ -z "$name" ]] && name="Agent"

                    paneInfo=$(echo "$panes" | grep "^${id}|")
                    if [[ -n "$paneInfo" ]]; then
                        cwd=$(echo "$paneInfo" | cut -d'|' -f4)
                        proj=$(basename "$cwd")

                        # capture content
                        content=$(tmux capture-pane -t "$id" -p 2>/dev/null | tail -20)
                        if echo "$content" | grep -qE "Allow once|Allow for this session|Allow in project|Do you want to proceed?|\[y/n\]"; then
                            state="needs-input"
                        fi

                        echo "${id}|${state}|${name}|${proj}|${cwd}"
                    fi
                fi
            fi
        done

        # Implicit process check fallback
        echo "$panes" | while IFS='|' read -r id pid tty cwd; do
            # Skip if already found in env
            if ! echo "$env" | grep -q "TMUX_AGENT_PANE_${id}_STATE"; then
                ttyShort=$(basename "$tty")
                cmd=$(ps -t "$ttyShort" -o command= 2>/dev/null)

                foundAgent=""
                for proc in claude .claude-wrapped gemini aider cursor; do
                    if echo "$cmd" | grep -q "$proc"; then
                        foundAgent=$proc
                        break
                    fi
                done

                if [[ -n "$foundAgent" ]]; then
                    cpu=$(ps -t "$ttyShort" -o %cpu= 2>/dev/null | awk '{s+=$1}END{print s}')
                    state="idle"
                    if (( $(echo "$cpu > 1.0" | bc -l) )); then state="running"; fi

                    content=$(tmux capture-pane -t "$id" -p 2>/dev/null | tail -20)
                    if echo "$content" | grep -qE "Allow once|Allow for this session|Allow in project|Do you want to proceed?|\[y/n\]"; then
                        state="needs-input"
                    fi

                    proj=$(basename "$cwd")
                    echo "${id}|${state}|${foundAgent}|${proj}|${cwd}"
                fi
            fi
        done
    ]=]}):start()
end

return M
