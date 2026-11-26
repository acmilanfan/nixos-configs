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
-- poll briefly before giving up.
local TITLE_POLL_INTERVAL = 0.04
local TITLE_POLL_TRIES = 15 -- ~0.6 s

-- Scans only running terminal apps: hs.window.allWindows() walks every app, corporate agents
-- included, which is what the watchers allowlist exists to avoid, and this polls up to 15x.
local function focusByTitle(title, onFail)
    local watchers = require("nanowm.watchers")
    local tries = 0
    local function attempt()
        -- AX is locked (breaker open / wake suppression): every call below would block.
        if watchers.axBlocked() then return end
        for _, app in ipairs(hs.application.runningApplications()) do
            if TERMINALS[app:name() or ""] then
                for _, win in ipairs(app:allWindows()) do
                    if win:title() == title then
                        focusWindowOnTag(win)
                        return
                    end
                end
            end
        end
        tries = tries + 1
        if tries >= TITLE_POLL_TRIES then
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

-- Title of the window the user invoked us from, but only when it is a terminal
-- we can raise. The chooser is frontmost once it is open, so showMenu captures
-- this before showing it.
local function frontTerminalTitle()
    local win = hs.window.focusedWindow()
    local app = win and win:application()
    if app and TERMINALS[app:name()] then
        return win:title()
    end
end

-- Last resort when no window carries the expected title. With several windows
-- of the same app this can raise the wrong one (all Ghostty windows share a
-- process), which is why focusAgent normally matches by title instead.
local function focusPidFallback(pids)
    local pid = pids and pids[1]
    if not pid then return end
    hs.task.new("/bin/ps", function(_, psOut)
        local termPid = findTerminalPid(pid, parseProcessTable(psOut))
        if termPid then focusByPid(termPid) end
    end, { "-eo", "pid,ppid,ucomm" }):start()
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
    if sourceTitle == nil then sourceTitle = frontTerminalTitle() end
    if sourceTitle == "" then sourceTitle = nil end

    local function apply(stdOut)
        local title, pids = parseFocusOutput(stdOut)
        -- The script printed no title (set-titles off, another terminal app): fall back to the
        -- old app-level focus. Its process-table walk stays in Lua so TERMINALS remains the
        -- single definition instead of being duplicated into shell.
        local function fallback() focusPidFallback(pids) end

        if not title then
            fallback()
            return
        end

        focusByTitle(title, function()
            if not sourceTitle then
                fallback()
                return
            end
            -- Positional arguments avoid shell-quoting the title: $1 is the pane,
            -- $2 the title of the window the user invoked us from.
            hs.task.new("/bin/zsh", function(exitCode, retryOut, retryErr)
                if exitCode ~= 0 then
                    -- 2 = the retry found no client to move; keep the old fallback.
                    if exitCode ~= 2 then
                        print("[NanoWM] focusAgent retry: tmux-focus-pane exited " .. tostring(exitCode) .. ": " .. tostring(retryErr))
                    end
                    fallback()
                    return
                end

                local retryTitle, retryPids = parseFocusOutput(retryOut)
                local function retryFallback() focusPidFallback(retryPids or pids) end
                if retryTitle then
                    focusByTitle(retryTitle, retryFallback)
                else
                    retryFallback()
                end
            end, { "-lc", 'tmux-focus-pane --source-title "$2" "$1"', "tmux-focus-pane", paneId, sourceTitle }):start()
        end)
    end

    hs.task.new("/bin/zsh", function(exitCode, stdOut, stdErr)
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
    end, { "-lc", "tmux-focus-pane " .. paneId }):start()
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
    local sourceTitle = frontTerminalTitle()
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
    -- switcher. Using "-lc" (login shell) for consistency with
    -- M.focusAgent's zsh invocation above and as a safety margin against
    -- PATH resolution depending on profile sourcing in other environments.
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
