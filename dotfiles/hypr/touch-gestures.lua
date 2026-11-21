-- ================================================================================
-- --- TOUCH GESTURES (yogabook; loaded only when touchGestures option is set) ---
-- ================================================================================
-- Touch gestures are handled by the yb-touchpad daemon; this file only holds
-- the device block and manual binds.

-- Manual launch / toggle bind (yb-touchpad window subcommand toggles).
-- The window is a layer-shell surface: no windowrules apply/needed.
hl.bind("SUPER + T", hl.dsp.exec_cmd("yb-touchpad window"))

-- Cycle dual-screen <-> virtual-laptop while detached.
hl.bind("SUPER + M", hl.dsp.exec_cmd("yb-mode cycle"))

-- The virtual touchpad is classified as a pointer device; enable touchpad
-- semantics explicitly so taps/scroll work on it.
hl.device({
  name = "yb-touchpad-virtual-touchpad",
  tap_to_click = true,
  tap_and_drag = true,
  clickfinger_behavior = true,
  scroll_method = "2fg",
  natural_scroll = true,
  sensitivity = 0.6,
  drag_lock = 1,
})
