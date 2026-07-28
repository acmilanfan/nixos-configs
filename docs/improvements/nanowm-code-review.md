# NanoWM / Hammerspoon Code Review (consolidated)

Consolidated, source-verified review of the Hammerspoon setup, focused on **nanowm**.

Supersedes `nanowm_code_review(claude).md` and `nanowm-code-review(deepseek).md`. Every
finding below was re-checked by reading the cited code; findings from those two documents
that did not survive verification are listed in
[§4 Rejected findings](#4-rejected-findings-do-not-re-raise) with the reason, so they don't
get re-raised.

**Scope:** `dotfiles/hammerspoon/init.lua` and all of `dotfiles/hammerspoon/nanowm/`
(config, state, core, layout, actions, tags, watchers, integrations, keybinds, menus,
overview, agents, pass, profiler, init) — 6,682 lines.

**Method:** every claim traced to source. API behaviour checked against the installed
`/Applications/Hammerspoon.app/Contents/Resources/docs.json` rather than assumed. Dead-code
claims verified by repo-wide grep including the sketchybar plugins and the tmux hooks in
`nixos/home-manager/common/tmux.nix`.

**Overall:** a well-architected personal WM. The Accessibility (AX) cost model — allowlist
`hs.window.filter`, circuit breaker, post-wake suppression, event-driven `_trackedWins` —
is the right design. The most valuable findings below are places where that model has
**gaps the design already anticipates elsewhere** (P2), and one perf profile that silently
never activates (P4). Line numbers are as of this review.

---

## 1. Fix first

### ~~P1. The profiler ships enabled, patches global functions, and flushes to disk per line~~ — ✅ DONE

> **Status: fixed** in `profiler.lua` and `nanowm/init.lua`. Both files compile
> (`loadfile` via the `hs` CLI). Not yet live: `~/.hammerspoon/` is populated from
> nix-store symlinks, so this takes effect after `darwin-rebuild switch` + an HS reload.
> See [§7 Change log](#7-change-log) for what was changed and one deliberate deviation
> from the fix described below.


- `profiler.lua:9` — `M.enabled = true`, with a header comment saying "Set false when done."
- `nanowm/init.lua:142,144` — `M.init()` unconditionally calls `profiler.patchGlobals()` and
  `profiler.startHeartbeat()`.
- `patchGlobals()` (`profiler.lua:92-108`) reassigns **global** `os.execute` and `hs.execute`
  process-wide, so every shell call in *all* Hammerspoon code is wrapped — AClock, VimMode,
  the caps-lock watcher, sweep-remapper, not just nanowm.
- Worse than previously reported: **`M.log` never checks `M.enabled`** (`profiler.lua:57-68`).
  So the global patches log unconditionally, and each line does both a `print()` to the HS
  console (line 66) and an `_fh:flush()` (line 42) — a synchronous disk write on the main
  event loop per shell call and per >30 ms callback.

Net effect: the instrumentation adds main-thread overhead to the exact hot path it exists to
measure, and it is on by default.

**Fix:** default `M.enabled = false` (gate on an `hs.settings` key or a marker file); guard
`M.log` with `if not M.enabled then return end`; skip `patchGlobals()`/`startHeartbeat()` in
`init()` unless enabled; buffer writes and flush on a timer instead of per line.

---

### P2. The AX circuit breaker doesn't cover the two hottest AX paths

This is the highest-value functional finding and neither source document caught it.

`_axCircuitOpen` is checked in exactly one place — `_resync` (`watchers.lua:110-113`). It is
**not** checked by either of the paths that call `allWindows()` far more often:

- `augmentAllWins()` (`watchers.lua:198-233`) — enumerates every allowlisted app, called from
  `windowFocused` (`watchers.lua:415`) and from `performTile` (`layout.lua:120`).
- the 1 s Firefox scanner (`watchers.lua:585-608`) — guarded by `_wakeSuppress` only.

So the moment AX goes slow enough to trip the breaker, the 60 s resync correctly backs off
while the per-focus and per-second scans keep hammering AX at full rate. Under a corporate
agent holding the AX lock (GlobalProtect / Falcon), this is precisely the freeze scenario the
breaker was written to prevent.

**Fix:** export the breaker state (e.g. `M.axBusy()`) and check it at the top of
`augmentAllWins` and the Firefox timer, as `_resync` already does. Consider also opening the
breaker from `augmentAllWins`' own slow-app detection (see P3) rather than only from
`_resync`.

---

### P3. `augmentAllWins` scans every app on every focus event, and silently drops slow apps

Same function as P2, two distinct problems:

**Scope.** The comment at `watchers.lua:196-197` says *"Scans the focused app for unmanaged
standard windows"*. The code scans **all** allowlisted apps (`watchers.lua:200-205`) and
ignores the focused app entirely. Running on every `windowFocused` (`watchers.lua:415`) means
every `Alt+J`/`Alt+K` and every mouse click triggers a full multi-app AX enumeration. The
stated justification (Firefox tab-detach windows) is already covered by the dedicated 1 s
Firefox scanner at `watchers.lua:585`.

**Silent data loss.** If one app's `allWindows()` takes ≥ 0.5 s its windows are skipped
entirely (`watchers.lua:218`); if the cumulative loop exceeds 2.0 s the remaining apps are
abandoned (`watchers.lua:211-213`). Both paths are silent, so a chronically slow app can keep
its windows permanently unmanaged with no signal. Note `_resync` logs its slow cases
(`watchers.lua:126-130`) — this function should too.

**Fix:** scope the per-focus call to the focused app; keep the broad sweep on the existing
60 s resync. Log (debug) when an app is skipped for slowness. Also fix the misindented block
at `watchers.lua:211-213`.

---

### P4. The AC performance profile never activates

`config.perf` defines an AC profile roughly 2× more aggressive than battery
(`config.lua:24-42`), but two of the three timers that consume it are built from the
**battery** constants and then never rebuilt:

- `layout.lua:21` — `hs.timer.delayed.new(config.perf.battery.tileDelay, ...)` → 0.10 s
  instead of 0.05 s.
- `integrations.lua:122-123` — `hs.timer.delayed.new(config.perf.battery.sbarDelay, ...)` →
  0.30 s instead of 0.15 s.

The rebuild only happens in `onPowerChange`, which early-returns when the power source
matches what's already recorded:

```lua
-- integrations.lua:494-496
local isAC = hs.battery.powerSource() == "AC Power"
if isAC == state.acPower then return end  -- no change
```

…and `state.acPower` is **already initialised correctly at load** (`state.lua:123`). So on a
machine that boots on AC and stays there, `rebuildTileTimer()` and `rebuildSketchybarTimer()`
are never called and the battery delays apply permanently. (`setupEdgeTrigger` is fine — it
reads `state.perfProfile()` at call time, `integrations.lua:405`.)

The earlier framing of this as "slower until the battery watcher fires" understates it: absent
a physical unplug, it never corrects.

**Fix:** build both timers from `state.perfProfile()` instead of `config.perf.battery`, or
call `onPowerChange`-style rebuilds once at the end of `init()`. Two lines, measurable
latency win on every tile and every bar update.

---

### P5. `focusPip` runs an unguarded `hs.window.allWindows()` straight off a hotkey

`actions.lua:245` — `focusPip` (bound to `Alt+V`, `keybinds.lua:67`) calls
`hs.window.allWindows()`, the full-system AX enumeration that the allowlist filter, the
circuit breaker and `_trackedWins` all exist to avoid, with none of those guards.

Under an AX lock this freezes the event loop on a keypress.

**Fix:** resolve the PiP window from `_trackedWins` — `core.getAllVisibleWindows` already
tracks PiP by title (`core.lua:351`), and `isFloating` treats
`title == "picture-in-picture"` as floating (`core.lua:99`), so the window is in the tracked
set. Fall back to a single `hs.application.get("Firefox"):allWindows()` if a broader search is
really needed.

The same unguarded call exists in the emergency rescue hotkey (`init.lua:10`) — that one is
fine to leave, since it's a deliberate last-resort escape hatch.

---

### P6. Windows float on generic title substrings with no app check

`core.isFloating` matches title substrings with **no application guard**:

```lua
-- core.lua:90-97
local title = (win:title() or ""):lower()
for _, str in ipairs(config.floatingTitles) do
    if string.find(title, str:lower(), 1, true) then
        result = true
        break
    end
end
```

`config.floatingTitles` (`config.lua:72-85`) contains the specific terminal titles you'd
expect (`ORGINDEX`, `YAZI`, `wifitui`, `btui`, `weekenduo`) **and** four generic English
words: `"Copy"`, `"Move"`, `"Info"`, `"Task Switcher"` (`config.lua:81-84`).

Any window whose title contains those anywhere gets floated — a Firefox tab "How to Copy
Files in Bash", a Slack thread mentioning "Move", a doc titled "Release Info". The verdict is
then cached per window id (`core.lua:103`) and only re-evaluated on title change
(`watchers.lua:297`), so a window that floats once keeps floating.

**Fix:** make `floatingTitles` entries `{ app = "Alacritty", title = "YAZI" }` pairs (the
terminal ones are all Alacritty), or at minimum drop the four generic words. Note the
`focusOrCreateApp` and `openInAlacritty` poll paths *already* guard on app name
(`keybinds.lua:198,218`, `core.lua:441`) — `isFloating` is the only unguarded site.

---

### P7. Failed weekenduo launches leak a window filter and its AXObserver

`keybinds.lua:352-378` (`Alt+Shift+Z`):

```lua
local filter = hs.window.filter.new(false):setAppFilter(appName, {allowTitles = titlePattern})
filter:subscribe(hs.window.filter.windowAllowed, function(newWin)
    filter:unsubscribe()
    ...
end)
```

`unsubscribe()` happens **only inside the callback**. The 5 s safety timer
(`keybinds.lua:373-378`) resets `state.weekenduoLaunching` but never touches the filter. So
if the window never appears — launch failed, Firefox slow, title didn't match — the filter
stays subscribed, kept alive by the closure HS retains, holding an **AXObserver on Firefox**
forever. One leaked observer per failed attempt.

This matters more here than it would in a normal config: the whole architecture is built
around minimising the number of live AXObservers (`watchers.lua:74-76` uses
`filter.new(false)` specifically so that unwanted apps never get one).

**Fix:** hoist the filter to module scope and reuse one instance, and unsubscribe from the
safety timer as well as from the callback.

---

### P8. `moveWindowToTag` inserts floating windows into the tiled stack

`tags.lua:391-411` unconditionally does:

```lua
state.tags[id] = destTag
table.insert(state.stacks[destTag], 1, id)
table.insert(state.tagCreationOrder[destTag], id)
```

`registerWindow` deliberately does **not** do this for floating windows
(`core.lua:201-208`, gated on `if not isFloat`), and `toggleFloat` removes the id from the
stack when a window starts floating (`actions.lua:54-61`). `moveWindowToTag` skips that check.

The phantom id then survives cleanup: `getTiledWindows` filters the window out of the
returned list but keeps its id in `cleanStack` (`core.lua:238-247`, the `else` branch), so it
is never pruned.

This is not theoretical — `actions.bringWindowToCurrentContext` sets
`floatingOverrides[id] = true` and then calls `moveWindowToTag` (`actions.lua:160-165`), which
is the path behind `Alt+Y` (YAZI), `Alt+Shift+O/W/D/Y` (ORGINDEX), `Alt+Shift+Z` (weekenduo)
and the leader-mode equivalents. Every use of those keys adds a phantom.

**Observable symptom:** `swapWindow` reads the raw stack (`actions.lua:264,281-300`). With
phantom ids inflating it, `targetIdx` can land on a floating id; the swap succeeds in the
stack but `getTiledWindows` filters that entry out, so the visible layout doesn't change —
`Alt+Shift+J/L` appears to do nothing. This is the concrete mechanism behind the
"stack/order divergence" that the DeepSeek review flagged speculatively as #17.

**Fix:** guard the inserts in `moveWindowToTag` with `if not core.isFloating(win) then`,
mirroring `registerWindow`. Optionally add the `#stack ~= #order` warning as a canary.

---

## 2. Confirmed, lower priority

### Correctness

**M1. Persisted window-id state leaks across reboots.**
`state.tags`, `sticky`, `floatingOverrides`, `windowWidths`, `tagLastFocused`,
`tagCreationOrder` are written to JSON (`state.lua:248-274`) and reloaded verbatim with no
liveness check (`state.lua:177-201`). The hourly pruner only trims `floatingCache` and
`sizeCache` (`state.lua:71-76`); it *reads* `M.tags` to build `validIds`
(`state.lua:66-69`) but never removes dead ids **from** it. Cleanup depends entirely on
`windowDestroyed` events, so any missed destroy (AX lock, app crash, wake storm) leaks
permanently — and the leak is persisted, so it survives restarts and grows for the life of the
save file.
*Fix:* extend the pruner to drop ids absent from `_trackedWins` and from `hs.window(id)`,
guarded by the AX breaker (P2).

**M2. `appTagMemory` is destructively wiped at 1000 entries.**
`state.lua:81-84` — `if #keys > 1000 then M.appTagMemory = {} end`. All hand-curated tag
memory is discarded with no warning and no LRU. 1000 is low for years of use, and JSON
encoding 5–10k small entries is trivial.
*Fix:* raise the cap substantially and evict least-recently-used (requires storing a
timestamp alongside the tag), or drop the cap.

**M3. `_resync` drops minimized windows on every full rebuild.**
`watchers.lua:133` requires `not win:isMinimized()` while building the replacement table, and
`_trackedWins = fresh` (line 140) is a replacement, not a merge. An unminimized window is
untracked until `windowFocused` re-registers it or the next 60 s resync.
*Fix:* keep minimized windows tracked and filter them at query time in `getTiledWindows`.

**M4. `gotoTag(nil)` is reachable with 5+ screens.**
`focusNextMonitor` and `moveWindowToNextMonitor` derive `monitorIdx` as an index into
`hs.screen.allScreens()` (`tags.lua:162-168, 188-194`) and then read
`state.activeTags[monitorIdx]`. `activeTags` has four entries (`state.lua:41`), so with five
or more displays this passes `nil` into `gotoTag`, which sets `state.currentTag = nil`
(`tags.lua:220`) and corrupts tag state. Unlikely setup, cheap guard.

**M5. PiP resize leaves x/y unclamped.**
`actions.lua:378-415` floors `w`/`h` at 200 (lines 390, 408) but the PiP anchor arithmetic
adjusts `x`/`y` with no bounds (lines 384, 393, 402, 411), so it can walk a PiP window
off-screen.
*Fix:* clamp to the screen frame after each branch.

**M6. `toggleSketchybar` has no concurrency guard.**
`integrations.lua:140-165` — rapid toggling can stack multiple
`os.execute("... 'sketchybar &' &")` calls and start several instances.
*Fix:* a `sketchybarToggling` boolean, cleared in the callback.

**M7. `contentIsConfirm` can false-positive.**
`agents.lua:125` matches literal `[y/n]`/`[Y/n]` anywhere in the last 20 captured lines, and
lines 92-97 match phrases like "Do you want to proceed?" — ordinary terminal output trips
both. Impact is a wrong status icon only.

**M8. Crash-recovery window is 2 s.**
`core.lua:170` — apps that relaunch slower than 2 s (crash reporter, reopen dialog) miss tag
recovery and fall back to tag memory or the current tag. `pendingDestruction` entries are
cleaned after `destructionDelay` (0.5 s) anyway, so 5–10 s costs nothing. Design choice, not a
bug.

**M9. Rule `app`/`title` matching uses Lua patterns, not plain find.**
`core.lua:138,141` use `string.match`, so `.`, `%`, `[`, `-` in a rule are interpreted as
pattern metacharacters with no way to escape them. **Latent** — `config.rules` is currently
empty (`config.lua:102-105`) — but it's a trap for the first rule anyone writes.
*Fix:* `string.find(..., 1, true)`.

### Perf / architecture

**M10. Sketchybar is killed and restarted on every reload.**
`integrations.lua:448-479` — when sketchybar is running *and* enabled, `init()` still does
`pkill -x sketchybar` then relaunches it 0.5 s later, then fires two update timers. Visible
flicker on every `Ctrl+Alt+Shift+R`. The "refresh" intent is reasonable; the kill is not.
*Fix:* when already running and enabled, just `scheduleInit(1, M.updateSketchybar)`.

**M11. Dock-position cache is never invalidated.**
`core.lua:388-398` — `cachedDockPos` is read once via a blocking `hs.execute` and cached for
the process lifetime. Move the dock and `isMouseInDockArea` (and therefore dock-click tag
switching, `watchers.lua:470`) silently breaks until reload.
*Fix:* re-read on a slow timer, or invalidate on `hs.distributednotifications` for dock
changes.

**M12. Inconsistent shell invocation; several blocking calls on the main loop.**
The codebase mostly uses non-blocking `hs.task`, but there are 8 `os.execute` and 6
`hs.execute` sites left:
- `integrations.lua:338` — Kanata reload, `os.execute(cmd .. " &")`. Deliberate (comment at
  lines 336-337) and only ~1 ms of fork, but inconsistent with `switchKanata` immediately
  above it, which already uses `hs.task.new` (`integrations.lua:274`).
- `integrations.lua:143,177,183,453,455,465,470` — sketchybar start/kill.
- `pass.lua:28` — a blocking `find -L` over the password store, run synchronously from the
  `Alt+Shift+P` hotkey.
- `agents.lua:20,26` — blocking `hs.execute` helpers (only used by dead code, see M13).
- `keybinds.lua:101,500` and `menus.lua:349` — the SyncMon launcher, three copies of the same
  blocking `hs.execute` with a `> /tmp/syncmon_hs.log` redirect. Harmless, but the redirect is
  a debug leftover and the triplication should be one function.
- `core.lua:396` — dock orientation (see M11).

**M13. Dead code (all verified zero-caller by repo-wide grep).**
- `agents.getAgents` + `agents.getStatus` (`agents.lua:132-246`, ~115 lines) — **no callers
  anywhere**, including the sketchybar plugins and the tmux hooks in
  `nixos/home-manager/common/tmux.nix`, which only use `focusAgent` and `onAgentStateChange`.
  This is a full synchronous re-implementation of the async zsh logic in `showMenu`, so
  deleting it also removes the two-implementations-to-keep-in-sync problem at zero risk.
- `config.perf.*.cacheTTL` (`config.lua:26-29,36`) — documented as "getManagedWindows cache",
  but `getManagedWindows` is a plain iteration over `_trackedWins` with no TTL
  (`watchers.lua:183-189`). Actively misleading: the comment describes a cache that no longer
  exists.
- `watchers.invalidateManagedWinsCache` (`watchers.lua:191-193`) — an explicit no-op with no
  callers.
- `state.markNextWeekenduo` — written at `keybinds.lua:324,346`, declared at `state.lua:51`,
  never read.
- `state.lua:34-35` — `for i = 1, 20 do M.tagSnapshots[i] = nil end` plus the `"special"`
  line, both no-ops after `M.tagSnapshots = {}` on line 30.
- `nanowm/init.lua:92` — `M.toggleOverview = M.toggleOverview`, a self-assignment directly
  below the function's definition.

**M14. `_home()` is duplicated in five modules with a foreign hardcoded fallback.**
`state.lua:134`, `integrations.lua:12`, `profiler.lua:14`, `pass.lua:8`, `keybinds.lua:33` all
define the same helper falling back to `"/Users/" .. (os.getenv("USER") or "gentooway")`.
`init.lua:71` has a sixth copy of the `"gentooway"` literal. On macOS `HOME` is always set, so
the fallback only ever fires in a broken environment where silently building paths under a
non-existent user is the worst response.
*Fix:* one helper in `core`, and fail loudly instead of guessing a username.

**M15. Duplicated window classification.**
`raiseFloating` (`layout.lua:69-96`) and `performTile` PHASE 1 (`layout.lua:179-213`) compute
tag/sticky/PiP/float visibility separately, and have already drifted: `raiseFloating` includes
`winTag ~= state.special.tag` in its exclusion test (line 87), `performTile` doesn't (line
198). Already flagged in `nanowm_performance.md`.
*Fix:* one classifier in `core`, called by both.

**M16. Built-in display detection by negative name match, in four places.**
`watchers.lua:166`, `layout.lua:132,145`, `actions.lua:126` each hardcode
`name ~= "Built-in Retina Display" and name ~= "Color LCD"` to decide whether to subtract
`sketchybarHeight`. Any external monitor can be named anything, and the fourth site
(`actions.lua:126`, in `toggleFullscreen`) was missed by both source reviews.
*Fix:* one helper, matching positively on built-in names — or read sketchybar's
`--bar display=` config. (Whether the polarity is correct depends on your monitor setup;
verify before flipping it.)

**M17. `windowFocused` is a heavy handler.**
`watchers.lua:387-492` does window registration, `augmentAllWins` (P3), a floating
re-evaluation timer, tile-protection checks, `isFloating`, and dock-click detection (which
until M11 is fixed can block on `hs.execute`) — on every focus event. Fixing P3 removes most
of the cost; the remainder would benefit from a fast path (record last-focused id, update the
bar) versus a slow path on the existing timers.

### Cosmetic

**M18. Overview grid navigation wraps wrongly.**
`overview.lua:217-220` uses `% 11` (item count) for a 4×3 grid (`cols = 4`,
`overview.lua:34`). Vertical moves are correct mid-grid but wrap incorrectly at the edges —
`up` from tile 1 lands on 8, not 9. No crash is possible (see [R2](#4-rejected-findings-do-not-re-raise)).
*Fix:* compute row/col from `cols = 4` and clamp to 11.

**M19. Overview only covers tags 1–10 + special.**
The WM supports tags up to 20 via `Ctrl+Alt+1-9/0` (`keybinds.lua:78,83`), but the grid
renders 11 cards (`overview.lua:83`) and `M.show` collapses any current tag > 10 to 1
(`overview.lua:174`). So `Alt+Tab` from tag 11–20 highlights the wrong tag.

**M20. Keybind help menu has drifted from the real bindings.**
`menus.showKeybindMenu` (`menus.lua:295-460`) is hand-maintained:
- duplicate `category = "System"` sections at lines 342 and 413;
- mangled indentation at lines 339-355 (valid Lua, hard to edit safely);
- `Alt+1-9 "Go to tag 1-9"` always calls `gotoTag(1)` (line 329);
- `fn = nil` placeholders at lines 315, 316, 331, 379-382, so those entries do nothing when
  selected.
*Fix:* generate the list from the real bind table, or at least de-dupe System and fix the
misleading `fn`s.

**M21. `hs.window.animationDuration = 0` is set twice.**
`init.lua:61` and `nanowm/init.lua:147`. Keep the nanowm one — it owns window geometry.

**M22. `profiler.wrap` allocates per invocation in the tile timer.**
`layout.lua:22,28` — `profiler.wrap("performTile", function() M.performTile() end)()` builds
two closures every time the timer fires instead of wrapping once at module load. Negligible
cost, but it defeats the point of `wrap` returning a reusable function.

---

## 3. Worth preserving

- **The AX cost model.** Allowlist `hs.window.filter.new(false)` (`watchers.lua:74-88`),
  circuit breaker on `allWindows() > 1 s` (`watchers.lua:123-127`), 300 s post-wake
  suppression with documented reasoning (`watchers.lua:551-580`), event-driven `_trackedWins`.
  The inline comments explaining *why* (corporate agents holding the global AX lock, `win:id()`
  itself blocking) are genuinely valuable and should survive any refactor. P2 is a gap in this
  model, not an argument against it.
- **`pass.lua`.** Password never on a command line, clipboard marked
  `org.nspasteboard.ConcealedType` so Raycast/Maccy skip it, auto-clear after 45 s only if the
  clipboard still holds the same value (`pass.lua:105-119`). The `writeObjects` /
  `writeDataForUTI` calls are both correct per the installed HS docs.
- **Persistence.** `hs.settings` → JSON migration with a fallback path (`state.lua:204-244`),
  debounced `triggerSave`, two-level key repair for JSON's string-key coercion
  (`cleanNested`, `state.lua:163-174`).
- **Freeze diagnostics.** The `lastCallback`/`lastEvent` breadcrumb scheme
  (`profiler.lua:115-124`) and the `onFreeze` → extended-suppression feedback loop
  (`watchers.lua:529-549`), including the "never shorten an existing longer timer" check.
- Per-power-source perf profiles as a concept — see P4 for why they don't currently apply.

---

## 4. Rejected findings (do not re-raise)

These appeared in the two source reviews and did **not** survive verification.

**R1. `hs.pasteboard.writeObjects(password)` must be `{password}` — invalid.**
From the installed `docs.json`: `writeObjects(object, [name])`, *"an object **or table of
objects**… a lua string, which can be received by most applications that can accept text"*.
`pass.lua:108` is correct. (`writeDataForUTI` at line 109 is also correct: the documented
signature is `([name], uti, data, [add])` and the 3-arg form with a strict boolean `add` is
exactly the documented disambiguation.)

**R2. Overview modulo can yield index 12 and call `gotoTag(12)` — invalid.**
In Lua `x % 11` with a positive divisor yields 0–10, so all four expressions at
`overview.lua:217-220` produce 1–11. Index 12 is unreachable and `gotoTag(12)` can never
fire. The real residue is the edge-wrap error, recorded as M18 at cosmetic severity — not
critical.

**R3. `windowCreated` retry captures a stale window ID — invalid.**
Two independent reasons. `_reevaluateFloating` returns a *closure*
(`watchers.lua:250-263`), so `hs.timer.doAfter(1.0, M._reevaluateFloating(id))` is correct —
the reported snippet implies an immediate-call bug that isn't in the code. And CGWindowIDs do
not change for a live window, so the premise ("the AX object was recreated, so the ID
differs") is wrong. Worst case is a nil table lookup that no-ops.

**R4. `require()` in hot paths should be hoisted to module-level upvalues — reject.**
The dynamic requires at `layout.lua:37,69,119,120` and `tags.lua:559` are deliberate: they
break a `watchers` ↔ `layout` circular dependency. Hoisting would reintroduce the cycle. The
cost is a hash lookup in `package.loaded`. (The report also cites `actions.lua:559` in a
555-line file.)

**R5. Kanata switch *and* reload block on `os.execute` — half invalid.**
`switchKanata` already uses `hs.task.new` (`integrations.lua:274`); the cited lines 271/323
are script-path assignments, not exec calls. Only `reloadKanata` uses
`os.execute(cmd .. " &")` (`integrations.lua:338`), it has a documented rationale, costs ~1 ms
of fork, and runs on wake or manual trigger — not a hot path. Retained as a consistency nit in
M12, not as a high-priority item.

**R6. Sketchybar `/tmp/syncmon_hs.log` redirect is an information leak — overstated.**
A fixed command's output written to a local file. Cosmetic debug leftover; folded into M12.

**R7. Built-in display offset logic is "backwards" — unverifiable.**
The fragile hardcoded name match is real (M16). Whether external displays or the built-in
should receive the `sketchybarHeight` offset depends on which screens actually carry a bar,
which the code can't tell us and the review didn't establish. Don't flip the polarity on this
claim alone.

**R8. Floating-by-title has no app guard *in `focusOrCreateApp`* — wrong site.**
The cited `keybinds.lua:~223` poll path **does** guard with `app:name() == appName`
(`keybinds.lua:216-218`), as does the fast path (`keybinds.lua:198`) and
`core.openInAlacritty` (`core.lua:441`). The finding is real but the vulnerable site is
`core.isFloating` — see P6.

**R9. Wiping `appTagMemory` leaves stale references in the menus viewer — invalid mechanism.**
`M.appTagMemory = {}` rebinds the field; consumers `require("nanowm.state")` and index
`state.appTagMemory` fresh on each call, so no stale read occurs. The destructive wipe itself
is real — see M2.

**R10. `swapWindow` stack/order divergence — reframed.**
Filed as speculative ("currently unlikely… future changes could expose this"). It is in fact
reachable today, but via a mechanism the report didn't identify: `moveWindowToTag` inserting
floating windows into the tiled stack. See P8.

**R11. Fallback agent entries are never cleaned up — not a finding.**
The report's own conclusion is "acceptable for now — the chooser re-queries on every
`showMenu()` call". Correct, and the code path in question is dead anyway (M13).

**R12. No automated test coverage — deprioritised, not rejected.**
Factually true. For a single-user Hammerspoon config with no test harness and heavy reliance
on live AX state, the cost/benefit is poor compared with everything above. If any testing is
added, the pure functions are the place to start: `state.getWindowKey` normalisation,
`layout.applyLayout` geometry given a fixed window list, `core.isFloating` given a stubbed
window. Those need no AX access.

---

## 5. Suggested order of work

Grouped so each step is independently verifiable, cheapest-first within each group.

1. ~~**P1** — profiler off by default, guard `M.log`, buffer writes.~~ ✅ **DONE** — see §7.
2. **P4** — two one-line timer fixes. Immediate, measurable.
3. **P2 + P3** — circuit-breaker coverage and `augmentAllWins` scoping. Same function; do them
   together. This is the actual freeze/latency work the profiler was installed to find.
4. **P5, P6, P7, P8** — four independent, self-contained bug fixes.
5. **M13** — delete the dead code (≈130 lines), including the misleading `cacheTTL` comments.
   Do this before the M-series refactors so there's less surface to touch.
6. **M14, M21, M12** — shared `_home()`, duplicate `animationDuration`, consolidate the three
   SyncMon copies and the remaining `os.execute` sites.
7. **M1, M2** — state-pruning work. Needs the breaker from P2 to be safe.
8. **M10, M11, M20** — sketchybar restart, dock cache, keybind help menu.
9. Everything else in §2 as opportunity allows.

---

## 6. Verification after any change

- Reload with `Ctrl+Alt+Shift+R` and confirm no red errors in the HS console.
- Exercise: tag switch (`Alt+1..0`, `Ctrl+Alt+1..0`), overview (`Alt+Tab`) including edge
  wraps, float toggle (`Alt+Shift+Space`), swap (`Alt+Shift+J/L`) — **verify it visibly moves
  windows**, which is the P8 regression test — fullscreen (`Alt+F`), special tag (`Alt+S`),
  free mode (`Ctrl+Alt+F`), PiP focus + resize (`Alt+V`), Kanata switch, agent chooser
  (`Alt+A`), pass chooser (`Alt+Shift+P`), the ORGINDEX/YAZI/weekenduo launchers, and a full
  sleep/wake cycle.
- Multi-monitor: verify tag→screen mapping and the sketchybar offset on each screen after
  touching M16.
- After P1: confirm `~/.hammerspoon/nanowm_slow.log` stops growing, and that
  `os.execute`/`hs.execute` are no longer globally wrapped — check in the HS console that they
  are the stock functions.
- After P4: `hs.settings`-free check — print the live tile/sbar timer delays from the console
  while on AC and confirm they read 0.05 / 0.15.
- After P8: `Alt+Y`, then inspect `NanoWM.stacks[NanoWM.state.currentTag]` in the console and
  confirm the floating window's id is absent.

---

## 7. Change log

### P1 — profiler opt-in (`profiler.lua`, `nanowm/init.lua`)

**`profiler.lua`**

- `M.enabled` now derives from a setting instead of being hardcoded `true`:
  `M.enabled = hs.settings.get("nanowm_profiler") == true`. Unset → `false`, so it is off by
  default. Toggle from the HS console with
  `hs.settings.set("nanowm_profiler", true); hs.reload()`.
- **Buffered writes.** Replaced the per-line `_fh:flush()` with a batching writer: lines
  accumulate in `_buf` and are written as one `table.concat` + a single flush, triggered by
  either a 5 s timer or a 200-line buffer cap. Rotation logic (`MAX_LINES = 8000`) preserved
  and moved into its own `rotate()`, now counting real lines written rather than assuming
  `MAX_LINES`.
- `writeLog` early-returns unless enabled, so no file is opened or touched when off.
- `M.flush()` exposed for forcing a write from the console, and `hs.shutdownCallback` is
  **chained** (not replaced) to flush on reload/quit — otherwise the last few seconds before a
  freeze-induced reload, the most interesting part, would be lost.
- `patchGlobals()` and `startHeartbeat()` early-return when disabled, so they are safe to call
  unconditionally from anywhere.

**`nanowm/init.lua`**

- `M.init()` only calls `patchGlobals()`/`startHeartbeat()` inside `if profiler.enabled then`,
  and prints a one-line notice when profiling is active so an accidentally-left-on profiler is
  visible in the console.

**Deliberate deviation from the fix as written above.** P1 prescribed guarding `M.log` itself
with `if not M.enabled then return end`. Implemented instead as: gate the **file write**, keep
the `print()` to the HS console unconditional. Rationale — once globals are unpatched, the
heartbeat is off and `M.wrap` returns the raw function, the only `M.log` callers still
reachable in the disabled state are three rare, high-value ones:

- `watchers.lua:126` — `"AX circuit open"`
- `watchers.lua:568,574` — `wake:suppress start` / `lifted`

(The `onFreeze` logs at `watchers.lua:534-545` are unreachable when disabled, since only the
heartbeat calls them; the sites at `watchers.lua:129`, `integrations.lua:118` and
`state.lua:287` are already individually gated on `profiler.enabled`.)

Fully gating `M.log` would silently discard exactly the AX diagnostics needed for the P2 work,
at a saving of a few `print()` calls per day. Preserving them costs nothing and keeps the
breaker observable with profiling off.

**Verification done:** both files compile (`loadfile` via the `hs` CLI — compile-only, the
running instance was not touched). Pre-change baseline recorded for comparison:
`~/.hammerspoon/nanowm_slow.log` at 1163 lines / 65 KB and actively growing.

**Verification still outstanding** (needs deployment — the files under `~/.hammerspoon/` are
nix-store symlinks, so repo edits are not live until `darwin-rebuild switch`):

1. `darwin-rebuild switch`, then reload Hammerspoon.
2. Confirm no `[prof]` spam in the console and that `nanowm_slow.log` stops growing.
3. Confirm the globals are unwrapped — in the console, `os.execute` and `hs.execute` should be
   the stock functions, and no "profiler ENABLED" line should appear at startup.
4. Round-trip the toggle: `hs.settings.set("nanowm_profiler", true); hs.reload()` → the
   notice appears, the log resumes, and entries land in ≤ 5 s batches rather than one at a
   time. Then set it back to `false`.
