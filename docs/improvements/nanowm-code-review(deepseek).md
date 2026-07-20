# NanoWM Code Review

## Critical / Likely Bugs

### 1. `pass.lua:107` — `writeObjects` receives a string, not a table

```lua
hs.pasteboard.writeObjects(password)  -- should be {password}
```

`hs.pasteboard.writeObjects` expects a **table** of objects. Passing a bare string relies on undefined Lua/C API cross-call behavior and may fail silently, corrupt the pasteboard, or not set the concealed type properly on certain Hammerspoon versions. This affects **all** pass operations (copy, generate, add).

**Fix:**
```lua
hs.pasteboard.writeObjects({password})
```

---

### 2. `overview.lua:216-223` — Grid navigation uses wrong modulo base

```lua
if dir == "right" then selectedIndex = (selectedIndex % 11) + 1
elseif dir == "left" then selectedIndex = (selectedIndex - 2) % 11 + 1
elseif dir == "down" then selectedIndex = (selectedIndex + 3) % 11 + 1
elseif dir == "up" then selectedIndex = (selectedIndex - 5) % 11 + 1
```

The 4×3 grid has 12 positions but only 11 items. The modulo uses `11` (item count) instead of `12` (grid size). When navigating **up** from index 1 (top-left), the result is `(1-5)%11+1 = 8` instead of the expected `9` (first column of bottom row). This also can produce `selectedIndex = 12` (nonexistent), meaning no card would be highlighted and `confirm()` would call `tags.gotoTag(12)` — an invalid tag.

**Fix:** Use modulo 12, then wrap/remap index 12:
```lua
-- Use grid size (12) for modulo, then handle the missing 12th position
local newIdx
if dir == "right" then newIdx = (selectedIndex % 12) + 1
elseif dir == "left" then newIdx = (selectedIndex - 2) % 12 + 1
elseif dir == "down" then newIdx = (selectedIndex + 3) % 12 + 1
elseif dir == "up" then newIdx = (selectedIndex - 5) % 12 + 1
end
selectedIndex = newIdx > 11 and 1 or newIdx
```

---

### 3. `state.lua:84` — Tag memory is destructively purged when >1000 entries

```lua
if #keys > 1000 then M.appTagMemory = {} end
```

All user-cultivated tag memory is silently wiped with no warning, no LRU eviction. Any code holding a reference to the old `M.appTagMemory` (e.g., the `menus.lua` "Show Tag Memory" viewer) would read stale data. 1000 entries is also a very low threshold for years of daily use.

**Fix:** Implement a proper pruning strategy. Track last-access time per entry and evict the least recently used entries, keeping a reasonable cap (e.g., 5000). Or simply remove the cap — JSON serialization of 1000 entries is trivial.

---

## High-Impact Issues

### 4. `integrations.lua:454-479` — `init()` restarts sketchybar unconditionally

Even when sketchybar is already running correctly, `init()` calls `pkill -x sketchybar`, starts a timer to re-launch it, then fires another timer for updates. On every Hammerspoon reload, sketchybar gets killed and restarted. This causes visible flicker and was likely written for a debugging session.

**Fix:** Check if sketchybar is in the desired state before killing it:
```lua
if state.sketchybarEnabled and exitCode == 0 then
    -- Already running and should be — just refresh
    scheduleInit(1, function() M.updateSketchybar() end)
end
```

---

### 5. `core.lua:390-397` — Dock position cache never invalidated

```lua
if not cachedDockPos then
    cachedDockPos = hs.execute("defaults read com.apple.dock orientation ...")
end
```

If a user moves the dock from bottom to left, the cached value is never refreshed. The dock-click detection in `windowFocused` will silently break until Hammerspoon restarts.

**Fix:** Either remove the cache and re-read on each call (the shell command is fast), or add a `hs.timer` that re-reads every few minutes, or subscribe to `NSWorkspace` dock-change notifications via a watcher.

---

### 6. `watchers.lua:198-233` — `augmentAllWins()` scans all whitelisted apps on every focus event

The `windowFocused` handler calls `augmentAllWins()` unconditionally (line 415), iterating every allowed app's `allWindows()`. On a machine with many Firefox tabs, Slack workspaces, Finder windows, etc., this is an expensive AX burst on every `Alt+J/K` or mouse click. The comment justifies it for "Firefox tab-detach windows," but the scan is far broader than needed.

**Fix:** Either:
- Only scan the focused application (not all apps)
- Add a per-app cooldown (e.g., scan Firefox at most once every 2 seconds)
- Move this logic into the existing 1s Firefox scanner timer

---

### 7. `layout.lua:130-136` — Built-in display detection by name is fragile

```lua
if name ~= "Built-in Retina Display" and name ~= "Color LCD" then
    primaryFrame.y = primaryFrame.y + config.sketchybarHeight
```

External monitors can be named anything. The assumption that built-in displays don't need the offset is backwards — sketchybar is typically ON the primary/built-in display and the bar reduces the usable area. A more robust approach would track which screen(s) have sketchybar bars via the sketchybar config, or store the screen frame adjustments per-screen.

**Fix:** Match **positively** on common built-in names instead of negatively excluding them. Or better, read sketchybar's `--bar display=` configuration to determine which screen needs adjustment.

---

### 8. Floating-override by window *title pattern* throughout `core.lua`, `keybinds.lua`

Multiple places set `state.floatingOverrides[id] = true` based on title matching (e.g., `"ORGINDEX"`, `"YAZI"`, `"wifitui"`, `"btui"`, `"weekenduo"`). If a non-Alacritty window happens to have one of these strings in its title (e.g., a browser tab titled "YAZI tutorial" or "Weekenduo signup"), it gets incorrectly floated. The `keybinds.lua` `focusOrCreateApp` poll-and-float logic on line 223 does the same.

**Fix:** Always include an app name check alongside the title check:
```lua
if appName == "Alacritty" and string.find(title:lower(), lowerPattern, 1, true) then
    state.floatingOverrides[wid] = true
end
```

---

## Medium Issues

### 9. `keybinds.lua:346` — `markNextWeekenduo` is set but never read (dead code)

```lua
state.markNextWeekenduo = true  -- line 346
state.markNextWeekenduo = false -- line 324
```

This flag is written in two places but never gated on anywhere. It was likely intended to be checked in `registerWindow()` or the `windowCreated` handler to automatically mark the *next* Firefox window as weekenduo, but the gating code was never written. Dead code.

**Fix:** Either implement the gating logic or remove the flag.

---

### 10. `core.lua:134-136` — Rule `app` matching using `string.match` is accidental pattern

```lua
appMatch = string.match(appName:lower(), rule.app:lower()) ~= nil
```

`string.match("firefox", "firefox")` works because a literal matches itself. But `string.match("google chrome", "chrome")` would match — which is probably the intent (case-insensitive substring). However, this also means special pattern characters in `rule.app` (`.`, `%`, `[`, etc.) would be interpreted as Lua patterns. There's no way to escape them.

**Fix:** Use `string.find` with plain matching:
```lua
appMatch = string.find(appName:lower(), rule.app:lower(), 1, true) ~= nil
```

---

### 11. `watchers.lua:270-280` — `windowCreated` retry captures potentially stale window ID

```lua
hs.timer.doAfter(0.1, function()
    local retryId = win:id()
    if retryId and retryId ~= 0 then
        ...
        local captureId = retryId
        hs.timer.doAfter(1.0, M._reevaluateFloating(captureId))
    end
end)
```

The `_reevaluateFloating` closure captures `captureId`, but 1.1 seconds after creation, the window may have a different ID if the AX object was recreated during the interim. `_reevaluateFloating` then looks up `_trackedWins[staleId]` and gets nil, silently failing to re-evaluate.

**Fix:** Re-lookup the window by the original `win` object reference in the closure, or verify the ID is still valid before proceeding.

---

### 12. `core.lua:169` — Crash recovery time window is only 2 seconds

```lua
if info.appName == appName and info.tag and (now - info.time) < 2.0 then
    recoveryTag = info.tag
```

If an app crashes and relaunches in >2s, the `pendingDestruction` entry has expired and the "remembered tag" fallback is used instead. This is usually fine, but if the app isn't in tag memory, it lands on the current tag instead of its previous one. 2 seconds is tight for applications that do crash reporting or reopen dialogs.

**Fix:** Bump to 5–10 seconds. The `pendingDestruction` entries are already cleaned up after `destructionDelay` (0.5s), so the memory overhead is negligible.

---

### 13. `integrations.lua:140-165` — `toggleSketchybar()` spawns chain of async tasks with no cancellation

```lua
hs.task.new("/bin/zsh", function(exitCode)
    ...
    os.execute("/bin/zsh -l -c 'sketchybar &' &")
    ...
end, { "-c", "pgrep -x sketchybar" }):start()
```

If the user rapidly toggles sketchybar, multiple `os.execute("sketchybar &")` processes can stack up, potentially starting multiple sketchybar instances. The inner `hs.task.new` on line 156 also starts unconditionally even if a previous one is running.

**Fix:** Guard with a boolean flag (`sketchybarToggling`) that prevents concurrent toggles, or use a single `hs.timer.delayed` approach.

---

### 14. `profiler.lua:142` — Profiler patches `os.execute`/`hs.execute` globally

This instruments EVERY subprocess call across ALL modules, not just NanoWM. The log file (`nanowm_slow.log`) will accumulate entries from `AClock`, `VimMode`, the caps lock watcher, the clock tick timer, and every sketchybar trigger. The `MAX_LINES=8000` rotation helps, but it's noisy and the patching can't be turned off without a code change.

**Fix:** Add a `profiler.enabled = false` check before each log write (already exists for some paths, but not the global patches), or scope the patching only to NanoWM call sites.

---

### 15. Repeated `_home()` function defined in 5 files

`state.lua:134-138`, `integrations.lua:12-16`, `keybinds.lua:33-37`, `pass.lua:8-12`, and `profiler.lua:14-17` all contain identical:

```lua
local function _home()
    local h = os.getenv("HOME") or ""
    if h:match("^/Users/") then return h end
    return "/Users/" .. (os.getenv("USER") or "gentooway")
end
```

**Fix:** Move to a shared utility module (e.g., `nanowm/util.lua` or add to `core.lua`) exported as `M.home()`. Also remove the hardcoded `"gentooway"` fallback — `os.getenv("HOME")` is always set on macOS.

---

## Low Severity / Code Quality

### 16. `state.lua:34-36` — Redundant initialization loop

```lua
for i = 1, 20 do M.tagSnapshots[i] = nil end
M.tagSnapshots["special"] = nil
```

These are already nil from `M.tagSnapshots = {}` on line 30. The four lines are no-ops. Remove them.

---

### 17. `actions.lua:262-325` — Stack and creation-order swaps could diverge

`swapWindow()` swaps in both `state.stacks[tag]` and `state.tagCreationOrder[tag]`. If the two lists have different contents (e.g., after certain operations that modify one but not the other), the swap indices may point to different windows. Currently unlikely because `toggleFloat()` adds to both in most code paths, but future changes could expose this.

**Fix:** Add an assertion or log warning when `#stack ~= #order` to catch divergence early.

---

### 18. `watchers.lua:132` — `_resync()` silently drops minimized and non-standard windows

```lua
if win:isStandard() and not win:isMinimized() then
    fresh[id] = win
end
```

Since `_resync()` is a full rebuild (not additive), any previously-tracked minimized window is dropped from `_trackedWins`. When unminimized later, it needs to be re-registered via `augmentAllWins()` or the next resync interval (up to 60 seconds away). During that window, the window won't tile correctly.

**Fix:** Keep minimized windows in `_trackedWins` but mark them so `getTiledWindows()` can filter them out. Or detect unminimize events.

---

### 19. `layout.lua:21` — Initial tile timer uses battery profile even on AC

```lua
local tileTimer = hs.timer.delayed.new(config.perf.battery.tileDelay, ...)
```

The timer starts with the battery delay (0.10s), and only switches to AC delay (0.05s) after the battery watcher fires `onPowerChange()`. On AC-powered machines, the first tiles are 2× slower than they should be until the battery watcher callback fires.

**Fix:** Read `state.acPower` at init time and create the initial timer with the correct profile:
```lua
local initialDelay = hs.battery.powerSource() == "AC Power"
    and config.perf.ac.tileDelay
    or config.perf.battery.tileDelay
local tileTimer = hs.timer.delayed.new(initialDelay, ...)
```

---

### 20. `agents.lua:184-216` — Fallback agent detection has no cleanup

Agents discovered via process detection (no `TMUX_AGENT_PANE_*` env var) persist until the next chooser call re-queries. If an agent process exits, its entry remains in the chooser until the user opens it again and the shell script re-runs.

**Fix:** Acceptable for now — the chooser re-queries on every `showMenu()` call. Just be aware that between refreshes, stale entries may appear.

---

### 21. `init.lua` (top-level) — `hs.window.animationDuration = 0` set twice

Both `dotfiles/hammerspoon/init.lua:61` and `nanowm/init.lua:147` set `hs.window.animationDuration = 0`. Redundant but not harmful.

**Fix:** Remove the top-level one in `init.lua` and let NanoWM manage it, since it's the window manager.

---

### 22. `actions.lua:378-416` — PiP resize logic is fragile

The `resizeFloatingWindow()` function has special PiP handling that manually computes anchor offsets to maintain aspect ratio. If macOS changes how PiP windows report their frame or if a non-video PiP appears, this logic can produce negative/wild frame coordinates.

**Fix:** Add bounds clamping after each PiP resize computation:
```lua
frame.x = math.max(0, frame.x)
frame.y = math.max(0, frame.y)
```

---

### 23. `keybinds.lua:100` — Stray debug output

```lua
hs.execute("/bin/zsh -l -c 'alacritty --title \"SyncMon Dashboard\" -e syncmon &' > /tmp/syncmon_hs.log 2>&1")
```

Redirecting to `/tmp/syncmon_hs.log` is a debug leftover. It writes to a file that never gets cleaned up and may leak information about launched commands.

**Fix:** Remove the redirection or use `/dev/null`.

---

## Architectural Observations

### 24. `windowFocused` handler is too heavy

`watchers.lua:387-492` — The `windowFocused` callback calls `augmentAllWins()`, sets up floating re-evaluation timers, scans for unmanaged windows, and checks dock-click detection — all on **every** focus event. On a busy workflow with `Alt+Tab` or `Alt+J/K` rapid-cycling, this generates significant AX traffic.

**Suggestion:** Split into fast-path (track last-focused window ID, update sketchybar) and slow-path (periodic augmentation via the existing 60s resync timer + the 1s Firefox scanner).

---

### 25. Module coupling through `require()` inside runtime hot paths

Multiple files call `require("nanowm.watchers").getManagedWindows()` dynamically in inner loops and hot paths:
- `layout.lua:37,69,119` (called in tile pipeline, raiseFloating)
- `actions.lua:559` (indirect through core/getTiledWindows)
- `tags.lua:559` (saveAllWindowTags)

Hammerspoon caches `require()` results, but each call still performs a table lookup. For functions called hundreds of times in tight loops, having a local upvalue is faster.

**Suggestion:** Move `require` calls to module level and cache the function reference:
```lua
local getManagedWindows = require("nanowm.watchers").getManagedWindows
```

---

### 26. No test coverage

~3500 lines of Lua with zero automated tests. The state machine, layout engine, and window registration logic would benefit from unit tests. Key areas to test:
- `getWindowKey()` normalization and exclusion
- `performTile()` layout computation (vertical/horizontal/mono/scrolling)
- Tag switching state transitions (fullscreen save/restore, last-focused tracking)
- `registerWindow()` crash recovery and rule matching

---

## Summary

| Severity | Count | Key Items |
|----------|-------|-----------|
| Critical | 3 | pass: broken pasteboard, overview: wrong grid navigation, state: destructive memory purge |
| High | 5 | Sketchybar restart on every reload, stale dock cache, per-focus AX scan, fragile display detection, overbroad floating by title |
| Medium | 7 | Dead code, pattern matching bugs, stale ID captures, tight crash-recovery window, concurrent toggle races, global profiler pollution, duplicated utility code |
| Low | 8 | Redundant code, potential list divergence, dropped windows, wrong initial timer config, stale agent entries, redundant settings, fragile PiP math, debug redirects |
| Architectural | 3 | Heavy windowFocused handler, hot-path require calls, no tests |

---

## Cross-Validation Against Claude Code Review

Reference: `docs/improvements/nanowm_code_review(claude).md` in same directory.

### Findings Confirmed By Both Reviews (Validated)

| Deepseek | Claude | Finding |
|----------|--------|---------|
| #14 | H1 | Profiler enabled in production, globals patched, per-line flush |
| #15 | L3 | `_home()` duplicated 5× with hardcoded `gentooway` fallback |
| #21 | L4 | `hs.window.animationDuration = 0` set twice |
| #9 | L2 | Weekenduo state has dead/drifted logic (different details, same area) |

Additionally, #4 (sketchybar restart on reload) is implicitly reinforced by Claude's L7 (inconsistent shell strategy — `os.execute(&)` in integration paths that should use `hs.task`).

### Findings Unique to Deepseek (Missed by Claude)

| # | Severity | What Claude Missed |
|---|----------|--------------------|
| #1 | Critical | `hs.pasteboard.writeObjects(password)` should be `writeObjects({password})`. This is a genuine API misuse that could silently corrupt the pasteboard. |
| #2 | Critical | Overview grid navigation uses modulo 11 instead of 12, causing wrong wrap-around and potential `gotoTag(12)` on nonexistent tag. |
| #3 | Critical | `appTagMemory = {}` purge at 1000 entries is destructive; Claude's M1 addresses orphaned window IDs but not the tag-memory purge specifically. |
| #4 | High | Sketchybar restarted on every config reload. |
| #5 | High | Dock position cache never invalidated. |
| #6 | High | `augmentAllWins()` called on every focus event (Claude's M3 notes the silent drop, not the frequency). |
| #7 | High | Display detection by negative name match is fragile. |
| #8 | High | Floating-override by title alone risks false positives. |
| #10 | Medium | Rule `app` matching uses `string.match` (pattern) instead of `string.find` (plain). |
| #11 | Medium | `windowCreated` retry closure captures stale ID. |
| #12 | Medium | Crash-recovery time window only 2s. |
| #13 | Medium | Rapid `toggleSketchybar()` can stack multiple startup processes. |
| #16 | Low | Redundant `tagSnapshots[i] = nil` loop. |
| #17 | Low | Stack/creation-order list divergence risk in `swapWindow()`. |
| #18 | Low | `_resync()` drops minimized windows silently. |
| #19 | Low | Initial tile timer hardcodes battery delay. |
| #22 | Low | PiP resize can produce negative coordinates. |
| #23 | Low | Stray `/tmp/syncmon_hs.log` redirect. |
| #24 | Arch | `windowFocused` handler too heavy. |
| #25 | Arch | `require()` in hot paths. |
| #26 | Arch | No tests. |

### Findings Unique to Claude (Missed by Deepseek)

| # | Severity | What Deepseek Missed |
|---|----------|---------------------|
| H1 | High | Profiler flush-on-every-line: Deepseek's #14 noted global patching, but missed the per-line `_fh:flush()` disk write aspect. Good catch. |
| H2 | High | Blocking `os.execute(cmd .. " &")` for Kanata switch/reload: Deepseek noted general `os.execute` usage but didn't flag the Kanata path specifically. |
| H3 | High | `focusPip` calls unguarded `hs.window.allWindows()`: Deepseek noted the function uses `allWindows()` but didn't call out the missing circuit breaker. Important for corporate-agent environments. |
| M1 | Medium | Per-window state tables leak on missed destroy events: Deepseek noted general memory concerns but didn't recommend a periodic orphaned-id sweep. |
| M2 | Medium | `cacheTTL` config values are dead: Noted in config comments but the cache they reference no longer exists. Deepseek missed this config drift. |
| M3 | Medium | `augmentAllWins` silently drops slow-app windows: Deepseek noted the function's cost (#6) but not the silent data loss. |
| M4 | Medium | Two parallel agent-detection implementations: Deepseek missed the Lua sync path vs. zsh async path duplication. |
| L1 | Low | `M.toggleOverview = M.toggleOverview` dead self-assignment in `init.lua:92`. |
| L2 | Low | Weekenduo staleness check has a dead clause: `not hs.window(state.weekenduoWinId)` is always false. |
| L5 | Low | Keybind help menu drifted from real bindings (dup System section, wrong fn bodies, broken indentation). |
| L6 | Low | Duplicated window-classification in `performTile` + `raiseFloating` (noted in perf docs but unfixed). |
| L7 | Low | Inconsistent shell-invocation strategy across integrations/agents/pass. |
| L8 | Low | `contentIsConfirm` can false-positive on normal terminal output containing `[y/n]`. |

### Combined Fix Priority

Suggested execution order incorporating both reviews:

1. **H1 (both)** — Default profiler off; stop global patching; buffer log writes instead of per-line flush.
2. **I #1 (deepseek)** — Fix `writeObjects({password})` — one-line fix with immediate impact.
3. **I #2 (deepseek)** — Fix overview grid modulo (12 instead of 11, wrap index 12).
4. **H2 (claude)** — Convert Kanata switch/reload to `hs.task`.
5. **H3 (claude)** — Add circuit breaker to `focusPip`'s `allWindows()`.
6. **I #3 (deepseek)** — Implement LRU or remove cap on `appTagMemory`.
7. **I #4 (deepseek)** — Fix sketchybar restart-on-reload logic.
8. **M1 (claude)** — Periodic orphaned-id sweep behind circuit breaker guard.
9. **M2 (claude)** — Remove dead `cacheTTL` config + no-op invalidator.
10. **L1-L4 (both)** — Trivial cleanups (self-assignment, weekenduo clause, shared `_home()`, dup animationDuration).

Remaining findings from both reviews are lower-priority follow-ups.
