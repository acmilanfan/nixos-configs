# Hammerspoon / NanoWM Code Review

Review of the Hammerspoon setup, focused on **nanowm** — issues, potential problems,
improvement opportunities, and strange things. Findings are grouped by severity with exact
file/line references.

Scope reviewed: `dotfiles/hammerspoon/init.lua` and all of `dotfiles/hammerspoon/nanowm/`
(init, core, state, layout, watchers, config, actions, tags, integrations, keybinds,
profiler, overview, agents, menus, pass) — ~7.2k lines.

Overall: a genuinely well-architected personal WM. The Accessibility (AX) cost mitigations
(allowlist filter, circuit breaker, wake-suppress, event-driven `_trackedWins`) are
thoughtful and mostly correct. The findings below are refinements, not a rewrite.

---

## High priority

### H1. Profiler is enabled in production and monkeypatches globals
- `nanowm/profiler.lua:9` — `M.enabled = true`; header comment says "Set false when done."
- `nanowm/init.lua` `M.init()` calls `profiler.patchGlobals()` + `profiler.startHeartbeat()`.
- `patchGlobals()` (profiler.lua:92) reassigns **global** `os.execute` and `hs.execute`
  process-wide — every shell call in *all* Hammerspoon code (not just nanowm) is wrapped.
- `writeLog()` (profiler.lua:38) does `_fh:flush()` on **every** line = a synchronous disk
  write on the main event loop for every shell call and every >30ms callback.
- Net effect: the diagnostic instrumentation adds main-thread overhead to the exact hot
  path it's meant to measure, and it ships on by default.
- **Fix:** gate behind a flag that defaults off (e.g. `M.enabled = false` unless a debug
  file/`hs.settings` key is present); don't call `patchGlobals()`/`startHeartbeat()` in
  `init()` unless enabled; buffer log writes instead of flushing every line.

### H2. Blocking `os.execute(cmd .. " &")` for Kanata switch/reload
- `nanowm/integrations.lua:271` and `:323` build a shell script path and run it via
  `os.execute(... " &")`. `os.execute` blocks the event loop until `/bin/sh` forks, and the
  rest of the codebase already standardizes on non-blocking `hs.task`/`core.launchTask`.
- The profiler logs `os.execute` unconditionally precisely because it's a known blocker.
- **Fix:** switch to `hs.task.new(...)` / `core.launchTask(...)` like the other integrations.

### H3. `focusPip` calls `hs.window.allWindows()` with no circuit-breaker guard
- `nanowm/actions.lua` `focusPip` uses `hs.window.allWindows()` — the exact expensive AX
  enumeration the circuit breaker (`watchers._resync`) and caches exist to avoid, invoked
  directly from a hotkey with none of those guards.
- Under a corporate-agent AX lock (GlobalProtect/Falcon) this can freeze on keypress.
- **Fix:** resolve the PiP window from `_trackedWins`/known app windows, or wrap the call in
  the same AX-timing guard used in `_resync` and bail if AX is slow.

---

## Medium priority

### M1. Per-window state tables are never garbage-collected on missed destroy events
- `nanowm/state.lua` hourly `pruneTimer` only trims `floatingCache`/`sizeCache` and caps
  `appTagMemory` at 1000. Tables keyed by live window id (`state.tags`, `state.sticky`,
  `state.floatingOverrides`, creation-order, etc.) rely solely on `windowDestroyed` events.
- If a destroy event is missed (AX lock, app crash, wake storm) those ids leak forever.
  There's crash *recovery* (`pendingDestruction`) but no periodic reconciliation.
- **Fix:** add a low-frequency sweep (guarded by the AX circuit breaker) that drops ids no
  longer present in `_trackedWins` / live windows.

### M2. `cacheTTL` config + `invalidateManagedWinsCache` are dead / stale-documented
- `nanowm/config.lua:29,36` document `cacheTTL` (2.0s / 1.0s) as "getManagedWindows cache",
  but `watchers.getManagedWindows()` (watchers.lua:183) is a plain iteration over
  `_trackedWins` with no TTL cache, and `invalidateManagedWinsCache()` (watchers.lua:191) is
  an explicit no-op.
- Config drift: future maintenance will trust comments that no longer describe the code.
- **Fix:** remove `cacheTTL` (and the no-op invalidator) or restore an actual cache. Removing
  is simpler given the event-driven design.

### M3. `augmentAllWins` silently drops windows of slow apps
- `nanowm/watchers.lua:198` — if a single app's `allWindows()` takes ≥0.5s that app's windows
  are skipped entirely (never tracked); if the cumulative loop exceeds 2.0s remaining apps
  are abandoned. Both paths are silent.
- A chronically slow/hung app can keep its windows permanently unmanaged with no signal.
- **Fix:** log (debug) when an app is skipped for slowness so it's diagnosable.

### M4. `agents.lua` maintains two parallel implementations of agent detection
- `M.getAgents`/`M.getStatus` (Lua, synchronous `sh()`/`exec()` = blocking) and `M.showMenu`
  (async `hs.task` with the same logic re-expressed in a large embedded zsh script).
- Two copies of the confirm-prompt/tty/cpu heuristics to keep in sync; the sync Lua path
  blocks the event loop if called from a bar refresh.
- **Fix:** confirm callers of the sync path aren't on a hot timer; long-term, converge on the
  async task and drop the duplicate, or factor the shell into one script both call.

---

## Low priority / strange things

### L1. `M.toggleOverview = M.toggleOverview` — dead self-assignment
- `nanowm/init.lua:92`. Harmless (the function is defined directly above) but pure cruft;
  likely a leftover from a refactor. Delete it.

### L2. Weekenduo staleness check has a dead clause
- `nanowm/keybinds.lua:305`:
  `if existingWin and (not existingWin:application() or not hs.window(state.weekenduoWinId))`.
  Since `existingWin == hs.window(state.weekenduoWinId)`, the second clause is always false
  here; the condition reduces to `existingWin and not existingWin:application()`. Simplify.

### L3. `_home()` duplicated in 5 modules with a wrong hardcoded fallback
- `state.lua:134`, `integrations.lua:12`, `profiler.lua:14`, `pass.lua:8`, `keybinds.lua:33`
  each define the same `_home()` whose fallback is `"/Users/" .. (USER or "gentooway")` —
  a foreign username. If `HOME`/`USER` were ever unset it silently builds paths under a
  non-existent user. Low runtime risk, but copy-paste + wrong default.
- **Fix:** one shared helper (e.g. in `core` or a small `util`) and drop the `gentooway`
  literal in favor of failing loudly or using `hs.fs`/`os.getenv` only.

### L4. `hs.window.animationDuration = 0` set twice
- `init.lua:61` and `nanowm/init.lua:147`. Redundant; pick one owner.

### L5. Keybind help menu drifts from real bindings
- `nanowm/menus.lua` `showKeybindMenu` is a hand-maintained list: several `fn = nil` /
  `fn = function() end` placeholders, some `fn` that don't match the real action
  (e.g. "Alt+1-9 Go to tag" always calls `gotoTag(1)`), a duplicated `category = "System"`
  section (~342 and ~413), and visibly mangled table indentation around lines 338–360
  (valid Lua, hard to maintain).
- **Fix:** generate the help list from the actual bind table in `keybinds.lua`, or at least
  de-dupe the System section and fix the misleading `fn`s.

### L6. Duplicated window-classification logic (perf-doc item, still open)
- `performTile` and `raiseFloating` in `nanowm/layout.lua` classify windows separately;
  `docs/improvements/nanowm_performance.md` already calls for a single-pass classifier.
  Consolidating into one `core` classifier reduces AX calls and keeps the two in sync.

### L7. Inconsistent shell-invocation strategy
- Mix of `hs.task`/`launchTask` (non-blocking, good), `hs.execute` (blocking), and
  `os.execute(... &)` across integrations/agents/pass. Standardize on `hs.task` for anything
  not genuinely needed synchronously.

### L8. `contentIsConfirm` can false-positive
- `nanowm/agents.lua:90` matches `[y/n]` / "Do you want to proceed?" anywhere in the last 20
  captured lines — ordinary terminal output can trip it. Impact is cosmetic (wrong status
  icon), so low priority; tighten to the cursor/menu heuristics if it annoys.

---

## Things that are done well (worth preserving)
- AX cost model: allowlist `hs.window.filter`, circuit breaker on `allWindows() > 1s`,
  post-wake suppression, event-driven `_trackedWins`. This is the right architecture.
- `pass.lua`: password written via temp file (never on the command line), clipboard marked
  `org.nspasteboard.ConcealedType`, auto-clear after 45s only if unchanged. Solid.
- Persistence with `hs.settings` → JSON migration and debounced `triggerSave`.
- Perf profiles switched by AC/battery power source.

---

## Suggested fix order (if acting on this)
High/medium first, smallest-risk first:
1. **H1** — default profiler off; stop patching globals unless a debug flag is set; buffer log writes.
2. **H2** — convert Kanata switch/reload to `hs.task`.
3. **H3** — remove the unguarded `allWindows()` from `focusPip`.
4. **M1** — periodic orphaned-id sweep behind the circuit breaker.
5. **M2** — delete dead `cacheTTL` + no-op invalidator.
6. **L1–L4** — trivial cleanups (self-assignment, weekenduo clause, shared `_home()`, dup animationDuration).

M3, M4, L5–L8 are follow-ups.

## Verification (for any fixes applied)
- `hs.reload()` (or `Ctrl+Alt+Shift+R`) and confirm no red errors in the HS console.
- Exercise: tag switch (Alt+1..0), overview (Alt+Tab), float toggle, Kanata mode switch,
  agent chooser (Alt+A), pass chooser (Alt+Shift+P), sleep/wake cycle.
- With profiler default-off, confirm `~/.hammerspoon/nanowm_slow.log` stops growing and
  `os.execute`/`hs.execute` are no longer globally wrapped (check via console).
