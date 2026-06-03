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
        cacheTTL     = 0.05,  -- getManagedWindows cache (watchers.lua)
        winMapTTL    = 0.06,  -- id→window map cache (core.lua)
        sbarDelay    = 0.10,  -- sketchybar update debounce (integrations.lua)
        edgePoll     = 0.15,  -- mouse-edge polling interval (integrations.lua)
        tileDelay    = 0.02,  -- tile debounce (layout.lua)
    },
    battery = {
        cacheTTL     = 0.15,  -- longer TTL = fewer allWindows() calls on battery
        winMapTTL    = 0.20,
        sbarDelay    = 0.30,
        edgePoll     = 0.50,
        tileDelay    = 0.08,
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

-- Window titles that should float
M.floatingTitles = {
    "ORGINDEX",
    "YAZI",
    "wifitui",
    "btui",
    "FineTune",
    "Picture-in-Picture",
    "weekenduo",
    "SyncMon Dashboard",
    "Copy",
    "Move",
    "Info",
    "Task Switcher",
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
