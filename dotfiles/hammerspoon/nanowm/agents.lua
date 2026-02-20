-- =============================================================================
-- NanoWM AI Agents Module
-- Detect Claude Code / Gemini CLI sessions and focus their terminals.
--
-- Public API:
--   agents.getAgents()        → list of { pid, type, cwd, project }
--   agents.getStatus(pid,cwd) → "working" | "confirm" | "recent" | "idle"
--   agents.focusAgent(pid)    → switch tmux pane (or terminal) to the agent
--   agents.showMenu()         → hs.chooser picker with all agents
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
-- /bin/sh correctly handles single-quoted awk programs without extra quoting layers.
local function exec(cmd)
    return hs.execute(cmd) or ""
end

-- Zsh login shell for nix-PATH tools (tmux, sketchybar).
-- Single-quote the argument to avoid /bin/sh expanding awk $N vars.
local function sh(cmd)
    local escaped = cmd:gsub("'", "'\\''")
    return hs.execute("/bin/zsh -lc '" .. escaped .. "'") or ""
end

-- =============================================================================
-- Short-lived caches (shared across multiple getStatus calls in one showMenu)
-- =============================================================================

local _procsCache, _procsCacheTime = nil, 0
local _panesCache, _panesCacheTime = nil, 0

local function cachedProcs()
    local t = os.time()
    if not _procsCache or t - _procsCacheTime > 2 then
        local out = exec("ps -eo pid,ppid,ucomm")
        local procs = {}
        for line in out:gmatch("[^\n]+") do
            local pid, ppid, comm = line:match("^%s*(%d+)%s+(%d+)%s+(%S+)")
            if pid then procs[pid] = { ppid = ppid, ucomm = comm } end
        end
        _procsCache, _procsCacheTime = procs, t
    end
    return _procsCache
end

local function cachedPanes()
    local t = os.time()
    if not _panesCache or t - _panesCacheTime > 2 then
        _panesCache = sh("tmux list-panes -a -F '#{pane_pid} #{pane_id}' 2>/dev/null")
        _panesCacheTime = t
    end
    return _panesCache
end

-- =============================================================================
-- Process helpers
-- =============================================================================

-- Returns { [pid_str] = { ppid, ucomm } } — fresh call, used by focusAgent
local function getProcessTable()
    local out = exec("ps -eo pid,ppid,ucomm")
    local procs = {}
    for line in out:gmatch("[^\n]+") do
        local pid, ppid, comm = line:match("^%s*(%d+)%s+(%d+)%s+(%S+)")
        if pid then procs[pid] = { ppid = ppid, ucomm = comm } end
    end
    return procs
end

local function ancestorSet(pid, procs)
    local set = {}
    local cur = tostring(pid)
    for _ = 1, 25 do
        local info = procs[cur]
        local p = info and info.ppid
        if not p or p == "1" or p == "0" then break end
        set[p] = true
        cur = p
    end
    return set
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

-- Find the tmux pane ID for a given PID by walking the process ancestor tree.
local function findPaneForPid(pid, procs)
    local anc = ancestorSet(pid, procs)
    anc[tostring(pid)] = true
    for line in cachedPanes():gmatch("[^\n]+") do
        local panePid, paneId = line:match("^(%d+) (%%%d+)")
        if panePid and anc[panePid] then return paneId end
    end
    return nil
end

-- Return true if the given pane content shows an explicit confirmation prompt.
-- Caller captures the content and passes it in (avoids redundant tmux calls).
--
-- Strategy: avoid generic ❯+keyword matching (too many false positives from
-- Claude Code's normal TUI output). Instead use:
--  1. Specific Claude Code button/dialog strings.
--  2. TUI cursor (❯ ›) on a line whose ENTIRE content is just Yes/No/Deny.
--  3. Classic [y/n] prompt patterns.
local function contentIsConfirm(content)
    -- Claude Code permission dialog button labels (capital-A, exact phrases).
    -- "Allowed once" (past tense status) does NOT contain "Allow once" as substring.
    if content:find("Allow once")
    or content:find("Allow for this session")
    or content:find("Allow in project") then
        return true
    end

    -- Claude Code command confirmation dialog (numbered Yes/No options).
    if content:find("Do you want to proceed?") then
        return true
    end

    -- TUI menu cursor on a STANDALONE option keyword — nothing else on the line.
    -- Covers Gemini's "❯ Yes" / "❯ No" menus.
    -- UTF-8: ❯ = \xe2\x9d\xaf   › = \xe2\x80\xba
    local CURSOR  = "\xe2\x9d\xaf"
    local CURSOR2 = "\xe2\x80\xba"
    for line in content:gmatch("[^\n]+") do
        local s = line:match("^%s*(.-)%s*$")   -- trim surrounding whitespace
        local cur = s:sub(1, 3)
        if cur == CURSOR or cur == CURSOR2 then
            local rest = s:sub(4):match("^%s*(.-)%s*$"):lower()
            if rest == "yes" or rest == "no" or rest == "deny" then
                return true
            end
        end
    end

    -- Classic prompts
    return content:find("%[y/n%]") ~= nil
        or content:find("%[Y/n%]") ~= nil
        or content:find("%(y/n%)") ~= nil
end

-- =============================================================================
-- Agent discovery
-- =============================================================================

function M.getAgents()
    local agents = {}

    -- Claude Code: nix wraps the binary as ".claude-wrapped" (visible in ucomm).
    local psOut = exec("ps -eo pid,ucomm")
    for line in psOut:gmatch("[^\n]+") do
        local pid, comm = line:match("^%s*(%d+)%s+(.-)%s*$")
        if comm == ".claude-wrapped" then
            local cwd = exec("lsof -a -p " .. pid .. " -d cwd 2>/dev/null | awk 'NR>1{print $NF;exit}'"):gsub("%s+$", "")
            table.insert(agents, {
                pid     = pid,
                type    = "Claude",
                cwd     = cwd,
                project = cwd:match("([^/]+)$") or "?",
            })
        end
    end

    -- Gemini CLI: node process with /bin/gemini as last arg.
    -- Keep only session roots (child processes share a gemini parent).
    local psArgsOut = exec("ps -eo pid,ppid,ucomm,args")
    local gPids, gPPids = {}, {}
    for line in psArgsOut:gmatch("[^\n]+") do
        local pid, ppid, comm, args = line:match("^%s*(%d+)%s+(%d+)%s+(%S+)%s+(.-)%s*$")
        if comm and comm:match("^node") and args and args:match("/bin/gemini$") then
            gPids[pid] = true
            gPPids[pid] = ppid
        end
    end
    for p, pp in pairs(gPPids) do
        if not gPids[pp] then
            local cwd = exec("lsof -a -p " .. p .. " -d cwd 2>/dev/null | awk 'NR>1{print $NF;exit}'"):gsub("%s+$", "")
            table.insert(agents, {
                pid     = p,
                type    = "Gemini",
                cwd     = cwd,
                project = cwd:match("([^/]+)$") or "?",
            })
        end
    end

    return agents
end

-- =============================================================================
-- Status detection
-- =============================================================================

-- States (in priority order for the bar aggregate):
--   "working" — actively generating / executing tools (yellow)
--   "confirm" — pane shows yes/no or allow/deny prompt (red, needs immediate action)
--   "recent"  — state files updated < 30 min ago (purple, waiting for next message)
--   "idle"    — no recent activity (gray)
function M.getStatus(pid, cwd, agentType)
    local procs = cachedProcs()
    local paneId = findPaneForPid(pid, procs)

    -- 1. Confirm: capture pane once, check for yes/no or allow/deny prompt.
    if paneId then
        local content = sh("tmux capture-pane -t '" .. paneId .. "' -p 2>/dev/null | tail -20")
        if contentIsConfirm(content) then return "confirm" end

    end

    -- 2. Working detection (agent-specific):
    local pidList = tostring(pid)
    for p, info in pairs(procs) do
        if info.ppid == tostring(pid) then pidList = pidList .. "," .. p end
    end
    if agentType == "Claude" then
        -- Claude keeps one persistent ESTABLISHED connection even when idle
        -- (HTTP/2 keep-alive). Active tool use or streaming adds more.
        local conns = tonumber(exec("lsof -a -p " .. pidList .. " -i 2>/dev/null | grep -c ESTABLISHED") or "0") or 0
        if conns > 1 then return "working" end
    elseif agentType == "Gemini" then
        -- Gemini's API connections are too short-lived and its [INSERT] status
        -- bar is always visible. Use CPU usage as a proxy: idle → 0%, working → >0%.
        local cpu = tonumber(exec("ps -p " .. pidList .. " -o %cpu= 2>/dev/null | awk '{s+=$1}END{print s}'"):gsub("%s+$", "")) or 0
        if cpu > 0.5 then return "working" end
    end

    -- 3. Recent: state files updated within last 30 min → waiting for your reply
    local dir = (cwd and cwd ~= "" and cwd) or
        exec("lsof -a -p " .. pid .. " -d cwd 2>/dev/null | awk 'NR>1{print $NF;exit}'"):gsub("%s+$", "")
    if dir ~= "" then
        local stateDir = os.getenv("HOME") .. "/.claude/projects/" .. dir:gsub("/", "-")
        if exec("find " .. stateDir .. " -mmin -30 2>/dev/null | head -1"):gsub("%s+$", "") ~= "" then
            return "recent"
        end
        local geminiDir = os.getenv("HOME") .. "/.gemini/tmp/" .. (dir:match("([^/]+)$") or "")
        if exec("find " .. geminiDir .. " -mmin -30 2>/dev/null | head -1"):gsub("%s+$", "") ~= "" then
            return "recent"
        end
    end

    return "idle"
end

-- =============================================================================
-- Focus agent terminal
-- =============================================================================

function M.focusAgent(pid)
    pid = tostring(pid)

    local procs = getProcessTable()   -- fresh call: focusAgent runs async, avoid stale cache
    local anc = ancestorSet(pid, procs)
    anc[pid] = true

    local paneOut = sh("tmux list-panes -a -F '#{pane_pid} #{pane_id} #{session_name} #{window_index}' 2>/dev/null")
    for line in paneOut:gmatch("[^\n]+") do
        local panePid, paneId, session, winIdx = line:match("^(%d+) (%%%d+) (%S+) (%d+)")
        if panePid and anc[panePid] then
            sh(
                "tmux switch-client -t '" .. session .. "' 2>/dev/null; " ..
                "tmux select-window  -t '" .. session .. ":" .. winIdx .. "' 2>/dev/null; " ..
                "tmux select-pane    -t '" .. paneId .. "' 2>/dev/null"
            )
            local clientOut = sh("tmux list-clients -F '#{client_pid} #{session_name}' 2>/dev/null")
            local clientPid = nil
            for cl in clientOut:gmatch("[^\n]+") do
                local cp, cs = cl:match("^(%d+) (%S+)")
                if cs == session then clientPid = cp; break end
            end
            if not clientPid then clientPid = clientOut:match("^(%d+)") end
            if clientPid then
                local termPid = findTerminalPid(clientPid, procs)
                if termPid then focusByPid(termPid) end
            end
            return
        end
    end

    local parentPid = procs[pid] and procs[pid].ppid or pid
    local termPid = findTerminalPid(parentPid, procs)
    if termPid then
        focusByPid(termPid)
    else
        hs.alert.show("Could not locate terminal for agent PID " .. pid)
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
        local s = M.getStatus(ag.pid, ag.cwd, ag.type)
        table.insert(choices, {
            text    = STATUS_ICON[s]  .. ag.type .. ": " .. ag.project,
            subText = STATUS_LABEL[s] .. "  •  " .. (ag.cwd ~= "" and ag.cwd or "?"),
            uuid    = tostring(i),
        })
        local pid = ag.pid
        actions[tostring(i)] = function() M.focusAgent(pid) end
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
