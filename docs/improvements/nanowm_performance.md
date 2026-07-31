# NanoWM Performance Improvements

This document outlines identified areas for performance optimization in the NanoWM Hammerspoon implementation.

> **Status annotations added after the code review.** Items 4 and 5 are done, 1 and 2 are partly
> done, 3 is still open. Measurements and reasoning are in `nanowm-code-review.md`; see §0 there
> for overall state and the remaining backlog.

## 1. Single-Pass Window Classification — PARTLY DONE
The current `performTile` function in `layout.lua` iterates over all managed windows multiple times (classification, `getTiledWindows` for current tag, `getTiledWindows` for special tag).

**Optimization:**
- Perform a single pass over `allWins` at the start of `performTile`.
- Categorize windows into specialized tables: `tiledCurrent`, `tiledSpecial`, `floatingVisible`, and `toHide`.
- This eliminates redundant iterations and ensures each window's metadata (tag, floating status, etc.) is checked only once per tile cycle.

**Status:** classification itself is now single-sourced — `core.classifyWindow()` is the only
implementation and both `performTile` PHASE 1 and `raiseFloating` call it (review §13; they had
silently drifted apart beforehand). Still open: `performTile` continues to call
`getTiledWindows` once per visible tag, so the multi-iteration part of this item stands.

## 2. Reducing Accessibility API Calls — PARTLY DONE
Calls to the macOS Accessibility API (`win:isVisible()`, `win:isMinimized()`, `win:frame()`, `win:title()`) are the primary performance bottleneck.

**Optimizations:**
- **Minimize `isVisible()` and `isMinimized()`:** Rely more on internal `state.windowState[id].isHidden` and `state.tags` instead of polling the OS during tiling.
- **Title Caching:** Consolidate title-based checks (like "Picture-in-Picture" detection) into the single-pass classification pass.
- **Avoid redundant `win:frame()` reads:** In the hiding phase, skip the frame read if the internal state already confirms the window is parked.

**Status:** done for the PiP title check (folded into `classifyWindow`) and for `raiseFloating`,
which no longer reads `win:frame()` per window — it uses `core.isParked()`, backed by
`state.windowState[id].isHidden` (review §15). Note the related trap: macOS clamps a parked
window to ~40 px of visibility, so it never reports the coordinate the code sets, and every
`x >= 90000` test was silently dead (review §14). Still open: `getTiledWindows` calls
`isVisible()` and `isMinimized()` per window.

## 3. Screen Frame Caching — OPEN
`hs.screen.mainScreen():frame()` is called multiple times during a single `performTile` execution.

**Optimization:**
- Fetch the screen frame once at the beginning of `performTile`.
- Pass this frame as a parameter to `applyLayout` and other helper functions.

**Status:** not done. Unmeasured, so worth timing `screen:frame()` before acting — the review's
recurring lesson was that assumed costs were wrong in both directions (a dead-id
`hs.window(id)` cost 37 ms; `hs.application.get` on an absent app cost ~50 ms; rebuilding the
whole window map cost 0.05 ms).

## 4. Efficient Window Enumeration — DONE
`core.getWinMap()` calls `hs.window.allWindows()`, which is extremely expensive.

**Optimization:**
- Prioritize using the list from `require("nanowm.watchers").getManagedWindows()`.
- Since `hs.window.filter` is event-driven, it is significantly faster than polling the entire window list from the OS.

**Status:** done. `getWinMap()` no longer calls `hs.window.allWindows()`; it iterates the
event-driven `_trackedWins` via `getManagedWindows()`. The TTL cache that used to wrap it was
removed outright — it saved ~0.05 ms while introducing up to 2 s of staleness, which caused a
real bug: the first window opened after a tag switch or wake was never laid out (review §10).

## 5. Smart Hiding Optimization — DONE
**Optimization:**
- In the window hiding phase, if a window is known to be on another tag and not sticky/PIP, skip the `win:frame()` read.
- Immediately use the parked coordinates if the internal `isHidden` state is false.

**Status:** done. PHASE 2 short-circuits on `state.windowState[id].isHidden` before any AX call,
and the redundant coordinate test that followed it was removed (review §15).
