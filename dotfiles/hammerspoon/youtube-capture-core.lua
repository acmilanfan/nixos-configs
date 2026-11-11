-- No Hammerspoon globals: traversal and failure behavior are tested with fixtures.
local M = {}

local function videoCandidate(url)
    if type(url) ~= "string" then return false end
    local host, path = url:match("^https?://([^/]+)(/.*)$")
    host = host and host:lower()
    if host == "youtu.be" or host == "www.youtu.be" then return path ~= "/" end
    if host ~= "youtube.com" and host ~= "www.youtube.com" and host ~= "m.youtube.com" then return false end
    return path:match("^/watch%?") and path:match("[?&]v=[^&#]+") ~= nil
        or path:match("^/shorts/[^/?#]+") ~= nil or path:match("^/live/[^/?#]+") ~= nil
end

function M.new(adapter, options)
    options = options or {}
    local active
    local controller = {}
    local poll, restore, nextTab

    local function stopTimer(s)
        if s.timer then s.timer:stop(); s.timer = nil end
    end
    local function finish(s, message)
        if active ~= s then return end
        stopTimer(s)
        active = nil
        if adapter.traversalChanged then adapter.traversalChanged(false) end
        if message then adapter.notify(message) end
    end
    local function schedule(s)
        stopTimer(s)
        s.timer = adapter.schedule(0.05, function() if active == s then poll(s) end end)
    end
    local function focused(s)
        return adapter.isValid(s.window) and adapter.isFocused(s.window)
    end
    local function report(s, code, stdout, stderr)
        if active ~= s then return end
        local ok, result = false, nil
        if type(stdout) == "string" and #stdout <= 1024 * 1024 and stdout:match("^%s*{") and options.decode then
            ok, result = pcall(options.decode, stdout)
        end
        if not ok or type(result) ~= "table" then
            local detail = type(stderr) == "string" and stderr ~= "" and stderr:sub(1,200) or "invalid helper response"
            finish(s, "Save failed: " .. detail .. "; keep tabs open and retry")
            return
        end
        for _, key in ipairs({ "saved", "existing", "failed" }) do
            local n = result[key]
            if type(n) ~= "number" or n < 0 or n > 4096 or n % 1 ~= 0 then finish(s, "Save failed: invalid helper counts"); return end
        end
        local message = string.format("Saved: %d; existing: %d; skipped: %d; failed: %d", result.saved, result.existing, s.skipped, result.failed)
        if code ~= 0 or result.failed > 0 or result.error then
            message = "Save failed/partial — " .. message
            if type(result.error) == "string" and result.error ~= "" then message = message .. "; " .. result.error:sub(1, 200) end
            local failed = {}
            for _, item in ipairs(type(result.items) == "table" and result.items or {}) do
                if type(item) == "table" and (item.status == "failed" or item.status == "unavailable" or item.status == "invalid") then
                    if type(item.id) == "string" and #failed < 3 then failed[#failed + 1] = item.id end
                end
            end
            if #failed > 0 then message = message .. "; retry: " .. table.concat(failed, ", ") end
            message = message .. "; keep failed videos open"
        end
        finish(s, message)
    end
    local function dispatch(s)
        if not s.dispatch then finish(s, s.message); return end
        for _,tab in ipairs(s.tabs) do
            if not adapter.isValid(tab) then finish(s,"Capture incomplete: a collected tab closed; nothing saved");return end
        end
        if #s.urls == 0 then finish(s, "No YouTube video tabs found; skipped: " .. s.skipped); return end
        s.phase = "saving"
        stopTimer(s)
        if adapter.traversalChanged then adapter.traversalChanged(false) end
        adapter.notify("Saving " .. #s.urls .. " video(s)…")
        local ok = pcall(adapter.run, s.urls, function(code, out, err) report(s, code, out, err) end)
        if not ok then finish(s, "Save failed: helper could not start; keep tabs open and retry") end
    end
    restore = function(s, dispatchBatch, message)
        if active ~= s then return end
        stopTimer(s)
        s.dispatch, s.message = dispatchBatch, message
        if not focused(s) then finish(s, message or "Capture cancelled: window focus changed; nothing saved"); return end
        if not adapter.isValid(s.original) then finish(s, "Capture cancelled: original tab closed; nothing saved"); return end
        s.phase, s.tabDeadline = "restoring", adapter.now() + 5
        if adapter.selected(s.window) == s.original then dispatch(s); return end
        local ok = adapter.select(s.original)
        if not ok then finish(s, "Could not restore original tab; nothing saved"); return end
        schedule(s)
    end
    nextTab = function(s)
        if active ~= s then return end
        if s.index > #s.tabs then restore(s, true); return end
        local tab = s.tabs[s.index]
        if not focused(s) then finish(s, "Capture cancelled: window focus changed; nothing saved"); return end
        if not adapter.isValid(tab) then restore(s, false, "Capture incomplete: a tab closed; nothing saved"); return end
        s.target, s.phase, s.tabDeadline = tab, "reading", adapter.now() + 5
        if adapter.selected(s.window) ~= tab then
            local ok = adapter.select(tab)
            if not ok then restore(s, false, "Capture incomplete: could not select a tab; nothing saved"); return end
        end
        schedule(s)
    end
    poll = function(s)
        if active ~= s or s.phase == "saving" then return end
        if not focused(s) then finish(s, "Capture cancelled: window focus changed; nothing saved"); return end
        if s.phase == "restoring" then
            if adapter.selected(s.window) == s.original then dispatch(s)
            elseif adapter.now() >= s.tabDeadline then finish(s, "Could not confirm tab restoration; nothing saved")
            else schedule(s) end
            return
        end
        if adapter.now() >= s.deadline or adapter.now() >= s.tabDeadline then restore(s, false, "Capture incomplete: tab/URL readiness timed out; nothing saved"); return end
        if not adapter.isValid(s.target) then restore(s, false, "Capture incomplete: a tab closed; nothing saved"); return end
        if adapter.selected(s.window) ~= s.target then schedule(s); return end
        local url, err = adapter.readURL(s.window, s.target)
        if not url then
            if err == "pending" then schedule(s) else restore(s, false, "Capture incomplete: " .. (err or "URL unavailable") .. "; nothing saved") end
            return
        end
        if not (s.verifyFirst and s.index == 1) then
            if videoCandidate(url) then s.urls[#s.urls + 1] = url else s.skipped = s.skipped + 1 end
        end
        adapter.notify(string.format("Collected %d/%d tabs", s.index, #s.tabs))
        s.index = s.index + 1
        nextTab(s)
    end

    function controller.start(mode)
        if active then adapter.notify("YouTube capture/save is already running"); return false end
        if mode ~= "current" and mode ~= "window" then adapter.notify("Unknown capture action"); return false end
        local snapshot, err = adapter.snapshot()
        if not snapshot then adapter.notify("Capture failed: " .. (err or "Firefox accessibility unavailable")); return false end
        if mode == "window" and snapshot.complete == false then adapter.notify("Capture incomplete: " .. (snapshot.reason or "unsupported tab layout") .. "; nothing saved"); return false end
        local tabs, verifyFirst = {}, false
        if mode == "current" then
            if snapshot.verifyTab then tabs = {snapshot.verifyTab, snapshot.selected};verifyFirst = true
            else tabs = {snapshot.selected} end
        else
            -- A genuine first transition establishes page identity even when the
            -- tab strip's first tab was already selected at invocation time.
            for _,tab in ipairs(snapshot.tabs) do if tab ~= snapshot.selected then tabs[#tabs+1]=tab end end
            tabs[#tabs+1]=snapshot.selected
        end
        if not snapshot.selected or #tabs == 0 or #tabs > 4096 then adapter.notify("Capture failed: missing tabs or more than 4096 tabs"); return false end
        local s = { window = snapshot.window, original = snapshot.selected, tabs = tabs, verifyFirst=verifyFirst, index = 1, urls = {}, skipped = 0, deadline = adapter.now() + 120 }
        active = s
        if adapter.traversalChanged then adapter.traversalChanged(true) end
        nextTab(s)
        return true
    end
    function controller.cancel(reason)
        local s = active
        if not s or s.phase == "saving" or (s.phase == "restoring" and not s.dispatch) then return false end
        restore(s, false, (reason or "Capture cancelled") .. "; nothing saved")
        return true
    end
    function controller.busy() return active ~= nil end
    return controller
end

return M
