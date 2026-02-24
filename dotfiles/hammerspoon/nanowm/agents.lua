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

local function focusByPid(termPid)
    local app = hs.application.applicationForPID(termPid)
    if app then
        app:activate(true)
        hs.timer.doAfter(0.05, function()
            local win = app:focusedWindow() or app:mainWindow()
            if win then win:focus() end
        end)
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

    -- Gemini menu list (e.g., "3. Modify with external editor")
    if content:match("%d%. ") then
        return true
    end

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

    return content:find("%%[y/n%%]") ~= nil or content:find("%%[Y/n%%]") ~= nil
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
    local AGENT_PROCESSES = { "claude", ".claude-wrapped", "gemini", "node", "aider", "cursor" }
    for id, info in pairs(panes) do
        if not processedIds[id] then
            local ttyShort = info.tty:match("([^/]+)$")
            local psFull = exec("ps -t " .. ttyShort .. " -o command= 2>/dev/null")

            local foundAgent = nil
            for _, proc in ipairs(AGENT_PROCESSES) do
                if psFull:find(proc) then
                    if proc == "node" then
                        if psFull:find("gemini") then foundAgent = "Gemini"; break end
                    else
                        foundAgent = proc; break
                    end
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
-- NanoWM chooser menu
-- =============================================================================

local STATUS_ICON  = { working = "● ", confirm = "⚠ ", recent = "◉ ", idle = "○ " }
local STATUS_LABEL = { working = "working", confirm = "needs input", recent = "waiting", idle = "idle" }

local chooser = nil

function M.showMenu()
    local agents = M.getAgents()
    if #agents == 0 then
        hs.alert.show("No AI agents running")
        return
    end

    local choices, actions = {}, {}
    for i, ag in ipairs(agents) do
        local s = M.getStatus(ag.paneId)
        table.insert(choices, {
            text    = STATUS_ICON[s]  .. ag.type .. ": " .. ag.project,
            subText = STATUS_LABEL[s] .. "  •  " .. (ag.cwd ~= "" and ag.cwd or "?"),
            uuid    = tostring(i),
        })
        local paneId = ag.paneId
        actions[tostring(i)] = function() M.focusAgent(paneId) end
    end

    if chooser then chooser:delete() end
    chooser = hs.chooser.new(function(choice)
        if not choice then return end
        local fn = actions[choice.uuid]
        if fn then hs.timer.doAfter(0, fn) end
    end)
    chooser:width(55)
    chooser:bgDark(true)
    chooser:fgColor({ hex = "#FFFFFF" })
    chooser:subTextColor({ hex = "#CCCCCC" })
    chooser:placeholderText("Focus AI agent…")
    chooser:searchSubText(true)
    chooser:choices(choices)
    chooser:show()
end

return M
