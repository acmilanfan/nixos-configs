-- =============================================================================
-- NanoWM Configuration
-- All configurable settings and constants
-- =============================================================================

local M = {}

-- Version
M.VERSION = "v40"

-- Layout defaults
M.defaultMasterWidth = 0.5
M.gap = 0
M.layout = "tile"  -- "tile" or "monocle"

-- Timing
M.destructionDelay = 0.5
M.tagSwitchCooldown = 1.0
M.tileProtectionWindow = 0.5

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
    "Picture-in-Picture",
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
