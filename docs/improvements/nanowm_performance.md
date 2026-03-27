# NanoWM Performance Improvements

This document outlines identified areas for performance optimization in the NanoWM Hammerspoon implementation.

## 1. Single-Pass Window Classification
The current `performTile` function in `layout.lua` iterates over all managed windows multiple times (classification, `getTiledWindows` for current tag, `getTiledWindows` for special tag).

**Optimization:**
- Perform a single pass over `allWins` at the start of `performTile`.
- Categorize windows into specialized tables: `tiledCurrent`, `tiledSpecial`, `floatingVisible`, and `toHide`.
- This eliminates redundant iterations and ensures each window's metadata (tag, floating status, etc.) is checked only once per tile cycle.

## 2. Reducing Accessibility API Calls
Calls to the macOS Accessibility API (`win:isVisible()`, `win:isMinimized()`, `win:frame()`, `win:title()`) are the primary performance bottleneck.

**Optimizations:**
- **Minimize `isVisible()` and `isMinimized()`:** Rely more on internal `state.windowState[id].isHidden` and `state.tags` instead of polling the OS during tiling.
- **Title Caching:** Consolidate title-based checks (like "Picture-in-Picture" detection) into the single-pass classification pass.
- **Avoid redundant `win:frame()` reads:** In the hiding phase, skip the frame read if the internal state already confirms the window is parked.

## 3. Screen Frame Caching
`hs.screen.mainScreen():frame()` is called multiple times during a single `performTile` execution.

**Optimization:**
- Fetch the screen frame once at the beginning of `performTile`.
- Pass this frame as a parameter to `applyLayout` and other helper functions.

## 4. Efficient Window Enumeration
`core.getWinMap()` calls `hs.window.allWindows()`, which is extremely expensive.

**Optimization:**
- Prioritize using the list from `require("nanowm.watchers").getManagedWindows()`.
- Since `hs.window.filter` is event-driven, it is significantly faster than polling the entire window list from the OS.

## 5. Smart Hiding Optimization
**Optimization:**
- In the window hiding phase, if a window is known to be on another tag and not sticky/PIP, skip the `win:frame()` read.
- Immediately use the parked coordinates if the internal `isHidden` state is false.
