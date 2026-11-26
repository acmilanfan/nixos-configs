-- =============================================================================
-- NanoWM AI Agents Module
-- Detect Claude Code / Gemini CLI sessions and focus their terminals.
-- =============================================================================

local M = {}

-- Terminal app names (ucomm) we know how to focus
local TERMINALS = {
    ghostty = true, Ghostty = true,
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

-- focusAgent timing: one console line per switch, marking when each stage finished
-- (ms since the request). Off by default; turn on with require("nanowm.agents").traceFocus = true.
M.traceFocus = false

local function now() return hs.timer.absoluteTime() end

local function newTrace(paneId)
    if not M.traceFocus then return nil end
    return { pane = paneId, t0 = now(), parts = {} }
end

local function mark(tr, label)
    if not tr or tr.done then return end
    tr.parts[#tr.parts + 1] = string.format("%s@%.0f", label, (now() - tr.t0) / 1e6)
end

local function finishTrace(tr, outcome)
    if not tr or tr.done then return end
    mark(tr, outcome)
    tr.done = true
    print("[NanoWM] focusAgent " .. tr.pane .. " timing (ms): " .. table.concat(tr.parts, " "))
end

local function focusWindowOnTag(win, tr)
    local state = require("nanowm.state")
    local tags  = require("nanowm.tags")

    local tag = state.tags[win:id()]
    if tag and tag ~= state.currentTag then
        local started = now()
        -- gotoTag/toggleSpecial focus the tag's last-focused window 0.15 s after switching,
        -- which landed after our focus below: with two terminals on the tag, the plain shell
        -- focused there earlier won over the agent's window. Make the agent's the one they pick.
        state.tagLastFocused[tag] = win:id()
        if tag == "special" then
            if not state.special.active then
                tags.toggleSpecial()
            end
        else
            tags.gotoTag(tag)
        end
        mark(tr, string.format("tag-switch(%.0fms)", (now() - started) / 1e6))
    end
    hs.timer.doAfter(0.05, function()
        win:focus()
        finishTrace(tr, "focused")
    end)
end

-- Last resort when no window carries the expected title. With several windows of
-- the same app this can raise the wrong one (all Ghostty windows share a process),
-- which is why focusAgent normally matches by title instead.
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

-- Match the outer terminal title tmux gives the pane's clients (set-titles in
-- tmux.nix, printed by tmux-focus-pane). The title arrives as an OSC sequence, so
-- poll briefly before giving up. tmux-focus-pane forces the redraw before it exits,
-- and in timing logs every match landed on the first check; a miss means a hidden
-- surface, so waiting longer only delays the retry.
local TITLE_POLL_INTERVAL = 0.04
local TITLE_POLL_TRIES = 5 -- ~0.2 s

-- Scans only running terminal apps: hs.window.allWindows() walks every app, corporate agents
-- included, which is what the watchers allowlist exists to avoid, and this polls up to 15x.
local function findTerminalWindow(title)
    for _, app in ipairs(hs.application.runningApplications()) do
        if TERMINALS[app:name() or ""] then
            for _, win in ipairs(app:allWindows()) do
                if win:title() == title then return win end
            end
        end
    end
end

local function focusByTitle(title, onFail, tr, label)
    local watchers = require("nanowm.watchers")
    local tries, scanNs = 0, 0
    local function attempt()
        -- AX is locked (breaker open / wake suppression): every call below would block.
        if watchers.axBlocked() then
            finishTrace(tr, label .. "-ax-blocked")
            return
        end
        local started = now()
        local win = findTerminalWindow(title)
        scanNs = scanNs + (now() - started)
        tries = tries + 1
        if win then
            mark(tr, string.format("%s-hit(try %d, scans %.0fms)", label, tries, scanNs / 1e6))
            focusWindowOnTag(win, tr)
            return
        end
        if tries >= TITLE_POLL_TRIES then
            mark(tr, string.format("%s-miss(%d tries, scans %.0fms)", label, tries, scanNs / 1e6))
            onFail()
        else
            hs.timer.doAfter(TITLE_POLL_INTERVAL, attempt)
        end
    end
    attempt()
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

-- tmux-focus-pane output: title and the clients that now show the pane.
local function parseFocusOutput(stdOut)
    local title, pids
    for line in (stdOut or ""):gmatch("[^\n]+") do
        local t = line:match("^title=(.+)$")
        local pid = line:match("^client=%S+%s+(%d+)$")
        if t then
            title = t
        elseif pid then
            pids = pids or {}
            table.insert(pids, pid)
        end
    end
    return title, pids
end

local function isTerminalWindow(win)
    local app = win and win:application()
    return app ~= nil and TERMINALS[app:name() or ""] == true
end

-- Titles of terminal windows, best first, for the --source-title retry: the window the user
-- invoked us from, then terminals on visible tags (each tag's last-focused one first), then
-- terminals on hidden tags. tmux-focus-pane moves the first one that is actually a tmux client.
-- A single title was not enough: with several Ghostty windows it was often a plain shell, so
-- nothing moved and the fallback raised whichever Ghostty window was focused last. The chooser
-- is frontmost once it is open, so showMenu captures this before showing it.
local function terminalTitles()
    local state = require("nanowm.state")
    local core = require("nanowm.core")
    local titles, seen = {}, {}
    local function add(w)
        local t = w and w:title()
        if t and t ~= "" and not seen[t] then
            seen[t] = true
            titles[#titles + 1] = t
        end
    end

    local focused = hs.window.focusedWindow()
    if isTerminalWindow(focused) then add(focused) end

    local tags = {}
    if state.special.active then tags[#tags + 1] = state.special.tag end
    tags[#tags + 1] = state.currentTag
    for tag in pairs(require("nanowm.layout").visibleTagFrames()) do
        if tag ~= state.currentTag and tag ~= state.special.tag then tags[#tags + 1] = tag end
    end

    local terms = {}
    for _, w in ipairs(require("nanowm.watchers").getManagedWindows()) do
        if isTerminalWindow(w) then terms[#terms + 1] = w end
    end
    for _, tag in ipairs(tags) do
        local last = state.tagLastFocused[tag]
        for _, w in ipairs(terms) do
            if w:id() == last and not core.isParked(w, w:id()) then add(w) end
        end
        for _, w in ipairs(terms) do
            local id = w:id()
            if id and state.tags[id] == tag and not core.isParked(w, id) then add(w) end
        end
    end
    -- Hidden tags last: raising one switches to its tag, still better than a wrong window.
    for _, w in ipairs(terms) do add(w) end
    return #titles > 0 and titles or nil
end

-- Last resort when no window carries the expected title. With several windows
-- of the same app this can raise the wrong one (all Ghostty windows share a
-- process), which is why focusAgent normally matches by title instead.
local function focusPidFallback(pids, tr)
    finishTrace(tr, "pid-fallback")
    local pid = pids and pids[1]
    if not pid then return end
    hs.task.new("/bin/ps", function(_, psOut)
        local termPid = findTerminalPid(pid, parseProcessTable(psOut))
        if termPid then focusByPid(termPid) end
    end, { "-eo", "pid,ppid,ucomm" }):start()
end

-- Run tmux-focus-pane without a login shell (~70 ms per call). Hammerspoon's PATH lacks
-- the Home Manager profile, so env puts it first; the script finds tmux there too.
local USER_PROFILE_BIN = "/etc/profiles/per-user/" .. (os.getenv("USER") or "") .. "/bin"
local function focusPaneTask(callback, args)
    local argv = { "PATH=" .. USER_PROFILE_BIN .. ":" .. (os.getenv("HOME") or "") .. "/.nix-profile/bin:/usr/bin:/bin",
        "tmux-focus-pane" }
    for _, a in ipairs(args) do argv[#argv + 1] = a end
    return hs.task.new("/usr/bin/env", callback, argv)
end

function M.focusAgent(paneId, sourceTitle)
    -- paneId can come from hammerspoon://nanowm?cmd=focusAgent, which any local process (or a
    -- web page via the browser's open-app prompt) can open. tmux-focus-pane puts it inside a
    -- tmux format (-f "#{m:...}"), where #(...) would run a shell command, so accept only a
    -- real tmux pane id (%<n>).
    if type(paneId) ~= "string" or not paneId:match("^%%%d+$") then
        print("[NanoWM] focusAgent: ignoring invalid pane id " .. tostring(paneId))
        return
    end
    -- tmux-focus-pane (nixos/home-manager/common/scripts/tmux-focus-pane) does all the tmux
    -- work in one async invocation and prints the title its clients now carry. It selects the
    -- window/pane in the sessions that already show it instead of moving whichever client tmux
    -- considers current -- that used to switch an unrelated window's session, so focusing its
    -- client PID then raised the wrong window.
    --
    -- The title is the only reliable window identity: every Ghostty window belongs to one
    -- process, so the client PID identifies the app, never the window. Titles are tmux's
    -- set-titles-string (tmux.nix), and every client showing that window carries the same one.
    --
    -- A session's only client can be a hidden surface (background tab/split): selecting its
    -- window updates a title no OS window carries, so the match below fails and nothing appears
    -- to happen. Retry once with the title of the window the user is looking at; the script
    -- moves that visible client to the target session, giving the next match a real window.
    --
    -- Everything here is async: the sketchybar agent-focus plugin invokes this via `hs -c`, and
    -- blocking the event loop while an IPC request is in flight is what produced the
    -- `hs.ipc: already recursing` floods.
    -- sourceTitle: one title (a string, as from older callers) or a list, best first.
    local sourceTitles = sourceTitle
    if type(sourceTitles) == "string" then sourceTitles = sourceTitles ~= "" and { sourceTitles } or nil end
    if type(sourceTitles) ~= "table" or #sourceTitles == 0 then sourceTitles = terminalTitles() end
    local tr = newTrace(paneId)

    local function apply(stdOut)
        local title, pids = parseFocusOutput(stdOut)
        -- The script printed no title (set-titles off, another terminal app): fall back to the
        -- old app-level focus. Its process-table walk stays in Lua so TERMINALS remains the
        -- single definition instead of being duplicated into shell.
        local function fallback() focusPidFallback(pids, tr) end

        if not title then
            fallback()
            return
        end

        focusByTitle(title, function()
            if not sourceTitles then
                fallback()
                return
            end
            -- No shell involved, so the titles need no quoting.
            local retryArgs = {}
            for _, t in ipairs(sourceTitles) do
                retryArgs[#retryArgs + 1] = "--source-title"
                retryArgs[#retryArgs + 1] = t
            end
            retryArgs[#retryArgs + 1] = paneId
            focusPaneTask(function(exitCode, retryOut, retryErr)
                mark(tr, "retry-focus-pane")
                if exitCode ~= 0 then
                    -- 2 = the retry found no client to move; keep the old fallback.
                    if exitCode ~= 2 then
                        print("[NanoWM] focusAgent retry: tmux-focus-pane exited " .. tostring(exitCode) .. ": " .. tostring(retryErr))
                    end
                    fallback()
                    return
                end

                local retryTitle, retryPids = parseFocusOutput(retryOut)
                local function retryFallback() focusPidFallback(retryPids or pids, tr) end
                if retryTitle then
                    focusByTitle(retryTitle, retryFallback, tr, "title2")
                else
                    retryFallback()
                end
            end, retryArgs):start()
        end, tr, "title1")
    end

    focusPaneTask(function(exitCode, stdOut, stdErr)
        mark(tr, "focus-pane")
        if exitCode ~= 0 then finishTrace(tr, "exit-" .. tostring(exitCode)) end
        if exitCode == 1 then
            hs.alert.show("Could not locate tmux pane " .. tostring(paneId))
            return
        end
        if exitCode ~= 0 then
            -- 2 = no tmux client attached anywhere, so there is no window to raise.
            if exitCode ~= 2 then
                print("[NanoWM] focusAgent: tmux-focus-pane exited " .. tostring(exitCode) .. ": " .. tostring(stdErr))
            end
            return
        end
        apply(stdOut)
    end, { paneId }):start()
end

-- =============================================================================
-- Event-driven state change handler (called via hs IPC from tmux)
-- =============================================================================

-- Last notified state per pane (or per agent name when the caller has no pane,
-- e.g. an agent without hooks), so two agents of the same kind don't share one.
local lastNotifiedState = {}

local function terminalFrontmost()
    local app = hs.application.frontmostApplication()
    return app ~= nil and TERMINALS[app:name()] == true
end

-- paneId/where/focused come from the agent-state wrapper (tmux.nix): the tmux
-- pane, "session:window" for the message, and "1" if that pane is the active
-- one of an attached client.
function M.onAgentStateChange(agentState, agentName, paneId, where, focused)
    if not agentState or not agentName then return end
    if paneId == "" then paneId = nil end
    if where == "" then where = nil end
    local key = paneId or agentName

    -- Only notify once per state transition per agent
    if lastNotifiedState[key] == agentState then return end
    lastNotifiedState[key] = agentState

    if agentState == "off" then
        lastNotifiedState[key] = nil
        return
    end
    -- already looking at it
    if focused == "1" and terminalFrontmost() then return end

    local label = agentName:sub(1,1):upper() .. agentName:sub(2)

    if agentState == "needs-input" then
        -- Stays in Notification Center until dismissed; clicking it focuses the pane.
        -- One callback tag per pane, replaced in place: hs.notify.new(fn) would
        -- register a new uniquely tagged callback per notification and never drop it.
        -- Never unregistered, since an old notification can still be clicked.
        local tag = "nanowm-agent-input:" .. key
        hs.notify.register(tag, function()
            if paneId then M.focusAgent(paneId) end
        end)
        hs.notify.new(tag, {
            title = label .. " needs input",
            informativeText = where,
            soundName = hs.notify.defaultNotificationSound,
            withdrawAfter = 0,
        }):send()
    elseif agentState == "done" then
        hs.alert.show(label .. " finished" .. (where and ("  ·  " .. where) or ""), 3)
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
    -- The chooser is frontmost once shown, so capture the invoking window now.
    -- focusAgent uses its title to find (and if needed move) the visible client.
    local sourceTitle = terminalTitles()
    if chooser then chooser:delete() end
    chooser = hs.chooser.new(function(choice)
        if not choice then return end
        if choice.uuid and choice.uuid ~= "loading" then
            M.focusAgent(choice.paneId, sourceTitle)
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
    -- switcher. It runs through a login shell ("-lc") so PATH comes from the
    -- user's profile; unlike the focus path, the chooser is not latency-bound.
    hs.task.new("/bin/zsh", function(exitCode, stdOut, stdErr)
        if not chooser:isVisible() then return end

        -- A missing or failing script used to read as "No AI agents running".
        if exitCode ~= 0 then
            local msg = ((stdErr or ""):match("[^\n]+") or ""):sub(1, 120)
            chooser:choices({{
                text = "ai-agent-list failed (exit " .. tostring(exitCode) .. ")",
                subText = msg, uuid = "loading",
            }})
            return
        end

        local choices = {}
        for line in stdOut:gmatch("[^\n]+") do
            local paneId, status, typeName, project, cwd, title =
                line:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]*)|(.*)$")
            if paneId then
                local s = STATUS_MAP[status] or "working"
                -- Session description leads when the agent set one; the project stays
                -- searchable through cwd in the subtext.
                local name = (title ~= "") and title or project
                table.insert(choices, {
                    text    = STATUS_ICON[s] .. typeName .. ": " .. name,
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
