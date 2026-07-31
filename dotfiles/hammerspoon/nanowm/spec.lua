-- =============================================================================
-- NanoWM smoke tests
--
-- Run from the Hammerspoon console (or `hs -c`):
--     require("nanowm.spec").run()
-- then read the result a few seconds later:
--     require("nanowm.spec").report
--
-- These are integration tests against the LIVE window manager, deliberately. Every defect
-- found while reviewing this config was an integration or OS-behaviour bug rather than a logic
-- bug -- AX call cost, a cache TTL racing an event, macOS clamping window positions, sleep
-- being indistinguishable from a stall. Stub-based unit tests would have caught none of them.
--
-- Consequences of that choice, worth knowing before you run it:
--   * it mutates live state: opens and closes one window, and briefly switches tags
--   * it cannot run in CI -- it needs a GUI session, Hammerspoon, and Accessibility permission
--   * a few results depend on which apps happen to be running
--
-- Every mutating test restores what it touched via pcall + explicit teardown, so a failure
-- should not leave the WM in a broken state.
--
-- Deliberately NOT tested: anything requiring AX focus/z-order assertions. Too much stubbing
-- for too little signal.
-- =============================================================================

local config = require("nanowm.config")
local state   = require("nanowm.state")
local core    = require("nanowm.core")
local layout  = require("nanowm.layout")
local watchers = require("nanowm.watchers")

local M = {}
M.report = nil

-- =============================================================================
-- Tiny assertion harness
-- =============================================================================

local results = {}

local function pass(name, detail) results[#results + 1] = { true, name, detail } end
local function fail(name, detail) results[#results + 1] = { false, name, detail } end

local function check(name, cond, detail)
    if cond then pass(name, detail) else fail(name, detail) end
    return cond
end

-- Wrap a timer callback body. An error thrown inside hs.timer.doAfter is logged to the HS
-- console and the continuation never runs, so without this the whole chain stalls with no clue
-- where. `onErr` lets the caller keep the chain moving.
local function safely(label, fn, onErr)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            fail(label, "errored: " .. tostring(err))
            if onErr then pcall(onErr) end
        end
    end
end

local function lt(name, value, limit, unit)
    return check(name, value < limit,
        string.format("%.2f%s (limit %.2f%s)", value, unit or "", limit, unit or ""))
end

local function ms(fn)
    local t0 = hs.timer.secondsSinceEpoch()
    fn()
    return (hs.timer.secondsSinceEpoch() - t0) * 1000
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- =============================================================================
-- Suites: state integrity
-- =============================================================================

-- Regression cover for P9 / M1: state.tags grew to 799 entries against 10 live windows, and
-- the hourly reconciliation sweep cost ~29 s because it probed hs.window(id) per entry.
local function suite_state()
    local managed = #watchers.getManagedWindows()
    local tagged = count(state.tags)

    -- Allow a small transient margin: a window can close between these two reads.
    check("state.tags tracks live windows (no leak)", tagged <= managed + 3,
        string.format("managed=%d tagged=%d", managed, tagged))

    local live = {}
    for _, w in ipairs(watchers.getManagedWindows()) do live[w:id()] = true end

    local dead, phantoms, tiled = 0, 0, 0
    for _, stack in pairs(state.stacks) do
        for _, id in ipairs(stack) do
            if not live[id] then
                dead = dead + 1
            else
                local w
                for _, x in ipairs(watchers.getManagedWindows()) do if x:id() == id then w = x end end
                if w and core.isFloating(w) then phantoms = phantoms + 1 else tiled = tiled + 1 end
            end
        end
    end
    check("no dead window ids in stacks", dead == 0, string.format("dead=%d tiled=%d", dead, tiled))
    -- P8: moveWindowToTag used to insert floating windows into the tiled stack.
    check("no floating phantoms in stacks", phantoms == 0, string.format("phantoms=%d", phantoms))

    -- The sweep's expensive step, measured without mutating persisted state.
    local n = 0
    local dt = ms(function() n = #hs.window.allWindows() end)
    lt("full window enumeration is cheap", dt, 500, "ms")
    check("enumeration returned windows", n > 0, string.format("%d windows", n))
end

-- =============================================================================
-- Suite: classification (M15) and the parked-window authority
-- =============================================================================

local function suite_classify()
    local visibleTags = {}
    for _, t in ipairs(state.activeTags) do visibleTags[t] = true end

    local disagree, parkedAtSentinel = 0, 0
    for _, win in ipairs(watchers.getManagedWindows()) do
        local isVisible = core.classifyWindow(win, visibleTags)
        local parked = core.isParked(win)
        -- A window cannot be both visible on an active tag and parked off-screen.
        if isVisible and parked then disagree = disagree + 1 end
        -- Documents the macOS clamp: a parked window never reports the coordinate we set.
        if parked and win:frame().x >= 90000 then parkedAtSentinel = parkedAtSentinel + 1 end
    end

    check("classifyWindow and isParked never disagree", disagree == 0,
        string.format("disagreements=%d", disagree))
    check("parked windows are clamped by macOS, not at PARK_COORD", parkedAtSentinel == 0,
        "if this fails, coordinate sentinels would work again -- see section 14 of the review")
end

-- =============================================================================
-- Suite: floating classification by title (P6)
-- =============================================================================

-- Pure test: isFloating only calls id/application/title/isStandard on the window, so a stub
-- is enough. Uses ids far outside the real range and clears the cache afterwards.
local function fakeWin(id, appName, title)
    return {
        id = function() return id end,
        application = function() return { name = function() return appName end } end,
        title = function() return title end,
        isStandard = function() return true end,
        frame = function() return { x = 0, y = 0, w = 100, h = 100 } end,
    }
end

local function suite_floating_titles()
    local cases = {
        -- name, app, title, expected
        { "Alacritty ORGINDEX floats",        "Alacritty", "ORGINDEX-WORK",                          true  },
        { "Alacritty YAZI floats",            "Alacritty", "YAZI",                                   true  },
        { "Firefox weekenduo floats",         "Firefox",   "weekenduo.app - Mozilla Firefox",        true  },
        -- The live false positive that motivated scoping: bare "Info" matched "Information".
        { "Firefox 'Information' does NOT float", "Firefox", "Cost effective - General Information", false },
        { "Firefox 'Copy' does NOT float",     "Firefox",  "How to Copy Files in Bash",              false },
        { "ORGINDEX in a browser does NOT float", "Firefox", "ORGINDEX tutorial",                    false },
        { "PiP floats from any browser",       "Safari",   "Picture-in-Picture",                     true  },
    }
    local base = 900000
    for i, c in ipairs(cases) do
        local id = base + i
        local got = core.isFloating(fakeWin(id, c[2], c[3]))
        check(c[1], got == c[4], string.format("app=%q title=%q -> %s", c[2], c[3], tostring(got)))
        core.invalidateFloatingCache(id)
    end
end

-- =============================================================================
-- Suite: overview grid navigation (M18) -- pure
-- =============================================================================

-- 11 cells, 4 columns: row0 = 1-4, row1 = 5-8, row2 = 9-11 (last column empty).
-- The old modular arithmetic wrapped linearly, so "up" from cell 1 landed on 8 instead of 9.
local function suite_grid()
    local ov = require("nanowm.overview")
    if type(ov.gridStep) ~= "function" then
        return fail("overview.gridStep exists", "not exported")
    end
    local cases = {
        { 1,  "up",    9,  "wraps up into the same column, not linearly" },
        { 5,  "up",    1,  "plain row step up" },
        { 9,  "down",  1,  "wraps down to the top of the column" },
        { 8,  "down",  4,  "skips the gap in the partial last row" },
        { 4,  "up",    8,  "skips the gap going up" },
        { 11, "up",    7,  nil },
        { 11, "down",  3,  nil },
        { 1,  "right", 2,  nil },
        { 11, "right", 1,  "wraps to the first cell" },
        { 1,  "left",  11, "wraps to the last cell" },
    }
    for _, c in ipairs(cases) do
        local got = ov.gridStep(c[1], c[2])
        check(string.format("grid %s %s -> %d", c[1], c[2], c[3]), got == c[3],
            c[4] or string.format("got %s", tostring(got)))
    end
end

-- =============================================================================
-- Suite: applyLayout geometry -- pure, stub windows on a scratch tag
-- =============================================================================

local function stubWin(id)
    local f = { x = -1, y = -1, w = 1, h = 1 }
    return {
        id = function() return id end,
        frame = function() return { x = f.x, y = f.y, w = f.w, h = f.h } end,
        setFrame = function(_, nf) f.x, f.y, f.w, f.h = nf.x, nf.y, nf.w, nf.h end,
        raise = function() end,
        got = function() return f end,
    }
end

local function suite_geometry()
    local SCRATCH = 99          -- not a real tag
    local AREA = { x = 0, y = 0, w = 1000, h = 1000 }
    local GAP = 4

    local saved = {
        layout   = state.tagLayouts[SCRATCH],
        master   = state.masterWidths[SCRATCH],
        gap      = state.gap,
        borders  = state.bordersEnabled,
        fs       = state.isFullscreen,
    }
    local function restore()
        state.tagLayouts[SCRATCH]  = saved.layout
        state.masterWidths[SCRATCH] = saved.master
        state.gap                  = saved.gap
        state.bordersEnabled       = saved.borders
        state.isFullscreen         = saved.fs
    end

    local ok, err = pcall(function()
        state.gap = GAP
        state.bordersEnabled = false
        state.isFullscreen = false
        state.masterWidths[SCRATCH] = 0.5

        -- vertical, 2 windows: master left, one stacked right, no overlap, full coverage
        state.tagLayouts[SCRATCH] = "vertical"
        local a, b = stubWin(9001), stubWin(9002)
        layout.applyLayout({ a, b }, AREA, false, SCRATCH, {})
        local fa, fb = a.got(), b.got()
        check("vertical: master starts at the area origin", fa.x == AREA.x and fa.y == AREA.y,
            string.format("master=%d,%d", fa.x, fa.y))
        check("vertical: full height for both", fa.h == AREA.h and fb.h == AREA.h,
            string.format("h=%d/%d", fa.h, fb.h))
        check("vertical: exactly one gap between columns", fb.x - (fa.x + fa.w) == GAP,
            string.format("master ends %d, stack starts %d", fa.x + fa.w, fb.x))
        check("vertical: stack reaches the right edge", fb.x + fb.w == AREA.x + AREA.w,
            string.format("right edge=%d", fb.x + fb.w))

        -- vertical, 3 windows: stack splits vertically, no overlap, full coverage
        local c = stubWin(9003)
        layout.applyLayout({ a, b, c }, AREA, false, SCRATCH, {})
        local f2, f3 = b.got(), c.got()
        check("vertical/3: stack entries share a column", f2.x == f3.x,
            string.format("x=%d/%d", f2.x, f3.x))
        check("vertical/3: exactly one gap between stack rows", f3.y - (f2.y + f2.h) == GAP,
            string.format("first ends %d, second starts %d", f2.y + f2.h, f3.y))
        check("vertical/3: stack reaches the bottom edge", f3.y + f3.h == AREA.y + AREA.h,
            string.format("bottom=%d", f3.y + f3.h))

        -- horizontal, 2 windows: master on top
        state.tagLayouts[SCRATCH] = "horizontal"
        local d, e = stubWin(9004), stubWin(9005)
        layout.applyLayout({ d, e }, AREA, false, SCRATCH, {})
        local fd, fe = d.got(), e.got()
        check("horizontal: full width for both", fd.w == AREA.w and fe.w == AREA.w,
            string.format("w=%d/%d", fd.w, fe.w))
        check("horizontal: exactly one gap between rows", fe.y - (fd.y + fd.h) == GAP,
            string.format("master ends %d, stack starts %d", fd.y + fd.h, fe.y))
        check("horizontal: stack reaches the bottom edge", fe.y + fe.h == AREA.y + AREA.h,
            string.format("bottom=%d", fe.y + fe.h))

        -- mono: every window fills the area
        state.tagLayouts[SCRATCH] = "mono"
        local m1, m2, m3 = stubWin(9006), stubWin(9007), stubWin(9008)
        layout.applyLayout({ m1, m2, m3 }, AREA, false, SCRATCH, {})
        local allFull = true
        for _, w in ipairs({ m1, m2, m3 }) do
            local f = w.got()
            if not (f.x == AREA.x and f.y == AREA.y and f.w == AREA.w and f.h == AREA.h) then
                allFull = false
            end
        end
        check("mono: every window fills the work area", allFull, "all three identical to area")

        -- single window on a tiling layout fills the area (the case that regressed in section 10)
        state.tagLayouts[SCRATCH] = "vertical"
        local solo = stubWin(9009)
        layout.applyLayout({ solo }, AREA, false, SCRATCH, {})
        local fs = solo.got()
        check("single window fills the work area", fs.w == AREA.w and fs.h == AREA.h,
            string.format("frame=%dx%d", fs.w, fs.h))
    end)

    restore()
    if not ok then fail("applyLayout geometry", "errored: " .. tostring(err)) end
end

-- =============================================================================
-- Suite: AX cost guards (P2/P3/P5)
-- =============================================================================

local function suite_ax(done)
    -- The wake probe must stay orders of magnitude cheaper than a window enumeration,
    -- otherwise probing every 2 s would itself be the problem.
    --
    -- Warm up first. The very first call also loads the hs.axuielement extension (~28 ms
    -- measured), which is a one-time cost paid once per Hammerspoon load — not what a repeating
    -- poll pays. Measuring it made this assertion fail spuriously on the first run after a
    -- reload. Steady-state cost is ~0.07 ms, and the production threshold (AX_PROBE_OK) is
    -- 250 ms, so 5 ms leaves ~70x headroom over observed and 50x margin under the real limit.
    pcall(function()
        return hs.axuielement.systemWideElement():attributeValue("AXFocusedApplication")
    end)
    local dt = ms(function()
        pcall(function()
            return hs.axuielement.systemWideElement():attributeValue("AXFocusedApplication")
        end)
    end)
    lt("AX health probe stays far below its 250ms threshold", dt, 5, "ms")

    check("breaker is not stuck open", watchers.axBlocked() == false,
        "axBlocked()=" .. tostring(watchers.axBlocked()))

    -- P3: a focus event must scan one app, not every allowlisted app.
    local focused = hs.window.focusedWindow()
    local app = focused and focused:application()
    if not app then
        fail("augmentAllWins scoping", "no focused window to scope against")
        return done()
    end

    local scoped = ms(function() watchers.augmentAllWins({}, app) end)

    -- Wait out FULL_AUGMENT_COOLDOWN with a timer rather than hs.timer.usleep(): a blocking
    -- sleep here would stall the very event loop these tests exist to keep responsive.
    hs.timer.doAfter(1.2, function()
        local full = ms(function() watchers.augmentAllWins({}) end)
        local suppressed = ms(function() watchers.augmentAllWins({}) end)
        check("scoped scan is much cheaper than the full sweep", scoped * 3 < full,
            string.format("scoped=%.1fms full=%.1fms", scoped, full))
        lt("full-sweep cooldown suppresses the repeat", suppressed, 1.0, "ms")
        done()
    end)
end

-- =============================================================================
-- Suite: power profile plumbing (P4)
-- =============================================================================

-- P4: the tile timer was built from a hardcoded battery constant, so the AC profile never
-- applied. Forces the AC profile, measures the real debounce, and restores.
local function suite_perf(done)
    check("AC and battery profiles differ", config.perf.ac.tileDelay ~= config.perf.battery.tileDelay,
        string.format("ac=%.2f battery=%.2f", config.perf.ac.tileDelay, config.perf.battery.tileDelay))

    local origAC = state.acPower
    local orig = layout.performTile
    local t0
    local finished = false

    local function restore()
        layout.performTile = orig
        state.acPower = origAC
        pcall(function() layout.rebuildTileTimer() end)
    end

    local ok = pcall(function()
        state.acPower = true
        layout.rebuildTileTimer()
        layout.performTile = function(...)
            local dt = (hs.timer.secondsSinceEpoch() - t0) * 1000
            layout.performTile = orig
            local expected = config.perf.ac.tileDelay * 1000
            check("tile debounce follows the live power profile",
                math.abs(dt - expected) < 40,
                string.format("measured=%.0fms expected~%.0fms", dt, expected))
            restore()
            if not finished then finished = true; done() end
            return orig(...)
        end
        t0 = hs.timer.secondsSinceEpoch()
        layout.tile()
    end)

    if not ok then
        fail("tile debounce follows the live power profile", "test errored")
        restore()
        if not finished then finished = true; done() end
    end

    -- Safety net: if the tile never fires, restore anyway.
    hs.timer.doAfter(3.0, function()
        if not finished then
            fail("tile debounce follows the live power profile", "tile never fired")
            restore()
            finished = true
            done()
        end
    end)
end

-- =============================================================================
-- Suite: the reported regression -- first window on a tag must tile immediately
-- =============================================================================

-- Covers BOTH causes found: the winMap TTL staleness (section 10) and tileProtectionWindow
-- discarding the tile (section 13). Before those fixes the window kept its natural size.
local function suite_first_window_tiles(done)
    local origTag = state.currentTag

    -- Pick an empty tag with a real tiling layout; mono would mask the result.
    local target = nil
    for t = 2, 10 do
        if #(state.stacks[t] or {}) == 0 and state.getLayout(t) ~= "mono" then target = t break end
    end
    if not target then
        fail("first window on an empty tag is tiled", "no empty non-mono tag available")
        return done()
    end

    local pre = {}
    for _, w in ipairs(watchers.getManagedWindows()) do pre[w:id()] = true end

    local function teardown(newId)
        if newId then
            for _, w in ipairs(watchers.getManagedWindows()) do
                if w:id() == newId then pcall(function() w:close() end) end
            end
        end
        hs.timer.doAfter(0.8, safely("first-window suite (teardown)", function()
            pcall(function() require("nanowm.tags").gotoTag(origTag) end)
            done()
        end, done))
    end

    require("nanowm.tags").gotoTag(target)

    hs.timer.doAfter(1.0, safely("first-window suite (launch)", function()
        core.launchTask("/usr/bin/open", { "-n", "-a", "Alacritty" })

        -- 1.2 s is well inside the old failure window (winMapTTL was 1-2 s).
        hs.timer.doAfter(1.2, safely("first-window suite (assert)", function()
            local newId, obj
            for _, w in ipairs(watchers.getManagedWindows()) do
                if not pre[w:id()] then newId, obj = w:id(), w end
            end
            if not obj then
                fail("first window on an empty tag is tiled", "no new window appeared")
                return teardown(nil)
            end

            local tiled = #core.getTiledWindows(target)
            local f = obj:frame()
            local screen = hs.screen.mainScreen():frame()
            -- One window on a tiling layout should fill the work area, modulo the bar and gaps.
            local fillsWidth = math.abs(f.w - screen.w) < 80

            check("new window is in the tiled set immediately", tiled >= 1,
                string.format("tiledCount=%d", tiled))
            check("new window was actually laid out (not left at natural size)", fillsWidth,
                string.format("frame=%dx%d@%d,%d screen w=%d", f.w, f.h, f.x, f.y, screen.w))

            teardown(newId)
        end, function() teardown(nil) end))
    end, done))
end

-- =============================================================================
-- Runner
-- =============================================================================

local function render()
    local passed, failed = 0, 0
    local lines = {}
    for _, r in ipairs(results) do
        local okFlag, name, detail = r[1], r[2], r[3]
        if okFlag then passed = passed + 1 else failed = failed + 1 end
        lines[#lines + 1] = string.format("%s %s%s",
            okFlag and "  ok  " or "  FAIL", name, detail and ("  -- " .. detail) or "")
    end
    local header = string.format("nanowm spec: %d passed, %d failed", passed, failed)
    return header .. "\n" .. table.concat(lines, "\n")
end

-- Wrap an async suite so a throw inside a timer callback cannot silently kill the chain:
-- Hammerspoon logs the error to the console and the continuation is simply never called,
-- leaving M.report nil with no indication of where it stopped.
local function guarded(name, suite)
    return function(done)
        local ok, err = pcall(suite, done)
        if not ok then
            fail(name .. " (async)", "errored: " .. tostring(err))
            done()
        end
    end
end

function M.run()
    results = {}
    M.report = nil

    M.progress = "started"
    local function finish(why)
        M.progress = "finishing"
        if M.report then return end
        M.report = render() .. (why and ("\n  " .. why) or "")
        print(M.report)
    end

    -- Watchdog: always produce a report, even if an async suite stalls.
    hs.timer.doAfter(30, function()
        finish("(watchdog fired: an async suite never completed — see the HS console for errors)")
    end)

    -- Synchronous suites first.
    for i, suite in ipairs({ suite_state, suite_classify, suite_floating_titles,
                             suite_grid, suite_geometry }) do
        M.progress = "sync suite " .. i
        local ok, err = pcall(suite)
        if not ok then fail("sync suite " .. i .. " crashed", tostring(err)) end
    end
    M.progress = "sync done"

    -- Then the ones that must wait on real events, chained so they never overlap.
    guarded("suite_ax", suite_ax)(function()
        M.progress = "ax done"
        guarded("suite_perf", suite_perf)(function()
            M.progress = "perf done"
            guarded("suite_first_window_tiles", suite_first_window_tiles)(function()
                M.progress = "tiling done"
                finish(nil)
            end)
        end)
    end)

    return "nanowm spec running — read require('nanowm.spec').report in ~10s"
end

return M
