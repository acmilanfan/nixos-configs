-- =============================================================================
-- NanoWM Configuration
-- All configurable settings and constants
-- =============================================================================

local M = {}

-- Version
M.VERSION = "v40"

-- Layout defaults
M.defaultMasterWidth = 0.5
M.gap = 4
M.borderWidth = 4
M.layout = "vertical"  -- "vertical", "horizontal", "mono", "scrolling"

-- Timing
M.destructionDelay = 0.5
M.tagSwitchCooldown = 1.0
M.tileProtectionWindow = 0.5

-- Performance profiles (switched by battery watcher)
-- Battery values are the baseline; AC values are more aggressive.
M.perf = {
    ac = {
        sbarDelay    = 0.15,  -- sketchybar update debounce (integrations.lua)
        edgePoll     = 0.50,  -- mouse-edge polling interval (integrations.lua)
        tileDelay    = 0.05,  -- tile debounce (layout.lua)
    },
    battery = {
        sbarDelay    = 0.30,
        edgePoll     = 1.00,
        tileDelay    = 0.10,
    },
}

-- Focus management
-- Set to nil or false to disable automatic focus on empty tags
M.emptyTagFocusApp = "Finder"

-- Apps that should always float
M.floatingApps = {
    ["System Settings"] = true,
    ["Activity Monitor"] = true,
    ["Calculator"] = true,
    ["Raycast"] = true,
    ["Vicinae"] = true,
    ["Finder"] = true,
    ["Photo Booth"] = true,
    ["Archive Utility"] = true,
    ["App Store"] = true,
    ["Marta"] = true,
    ["Hammerspoon"] = true,
    ["Disk Utility"] = true,
    ["Dock"] = true,
    ["Control Center"] = true,
    ["Notification Center"] = true,
    ["Spotlight"] = true,
    ["SecurityAgent"] = true,
    ["CoreAuthUI"] = true,
    ["loginwindow"] = true,
    ["Force Quit Applications"] = true,
}

-- Window titles that should float.
--
-- Entries are either a bare string (matches any app — use only for titles specific enough
-- that no other window could contain them) or { app = "...", title = "..." } to require a
-- matching application name.
--
-- Prefer the scoped form: matching is a case-insensitive substring test, so a bare "Copy"
-- floated any window whose title merely contained the word — e.g. a Firefox tab named
-- "How to Copy Files". The result is cached per window id, so a false positive sticks
-- until the title changes.
M.floatingTitles = {
    -- Terminal scratchpads / TUIs, all launched into Alacritty
    { app = "Alacritty", title = "ORGINDEX" },
    { app = "Alacritty", title = "SCRATCHPAD" },
    { app = "Alacritty", title = "YAZI" },
    { app = "Alacritty", title = "wifitui" },
    { app = "Alacritty", title = "btui" },
    { app = "Alacritty", title = "SyncMon Dashboard" },
    -- App-specific windows
    { app = "FineTune", title = "FineTune" },
    { app = "Firefox",  title = "Weekenduo", exact = true },
    -- Specific enough to leave unscoped (PiP can come from any browser)
    "Picture-in-Picture",
    "Task Switcher",
    -- NOTE: bare "Copy", "Move" and "Info" were removed here. They were redundant — Finder
    -- and Marta already float wholesale via M.floatingApps — while matching any window whose
    -- title contained those words. If a dialog stops floating, re-add it scoped to its app,
    -- e.g. { app = "Nextcloud", title = "Copy" }.
}

-- Apps that can trigger urgent notifications
M.urgentApps = {
    ["Firefox"] = true,
    ["Safari"] = true,
    ["Google Chrome"] = true,
    ["Slack"] = true,
    ["Discord"] = true,
    ["Messages"] = true,
    ["Telegram"] = true,
    ["WhatsApp"] = true,
    ["Microsoft Teams"] = true,
    ["Zoom"] = true,
}

-- Window Rules Engine (Pattern matching)
M.rules = {
    -- Example: { app = "Firefox", title = "YouTube", tag = 4, float = false }
    -- { app = "System Settings", float = true }
}

-- Apps excluded from tag memory
M.excludedFromTagMemory = {
    ["Alacritty"] = true,
    ["Terminal"] = true,
    ["iTerm2"] = true,
    ["Finder"] = true,
    ["System Settings"] = true,
}

-- Special tag configuration
M.specialTag = "special"
M.specialPadding = 100
M.sketchybarHeight = 35

-- =============================================================================
-- Shared helpers
-- =============================================================================

-- Home directory, previously duplicated in five modules (state, integrations, profiler,
-- pass, keybinds) each with a fallback that built paths under a hardcoded foreign
-- username. Resolving "~" is both correct and username-agnostic.
function M.home()
    local h = os.getenv("HOME")
    if h and h ~= "" then return h end
    return hs.fs.pathToAbsolute("~") or "."
end

-- Modifier key shortcuts
M.modifiers = {
    alt = { "alt" },
    altShift = { "alt", "shift" },
    ctrlAlt = { "ctrl", "alt" },
    ctrlAltShift = { "ctrl", "alt", "shift" },
    cmdAlt = { "cmd", "alt" },
    cmdAltShift = { "cmd", "alt", "shift" },
    cmdAltShiftCtrl = { "cmd", "alt", "shift", "ctrl" },
}

return M
