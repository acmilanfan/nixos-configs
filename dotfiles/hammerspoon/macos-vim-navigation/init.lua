-- Source: https://github.com/arturgrochau/macos-vim-navigation
-- Keyboard-centric navigation for macOS via Hammerspoon.
-- removed ctrl and option mouse control
-- commented out Arc and ChatGPT stuff
-- adjusted mouse movements
-- commented out unused keybinds
local hs = hs
local modal = hs.hotkey.modal.new()
local mouse = hs.mouse
local screen = hs.screen
local eventtap = hs.eventtap
local window = hs.window
local app = hs.application
local canvas = hs.canvas
local timer = hs.timer
-- Scroll configuration
local scrollStep = 62
local scrollLargeStep = scrollStep
local scrollInitialDelay = 0.15
local scrollRepeatInterval = 0.05
-- Directional repeat settings
local directionInitialDelay = 0.05
local directionRepeatInterval = 0.15
-- Timer tables
local held = {}
local holdTimers = {}
local repeatInterval = scrollRepeatInterval
-- Natural scrolling
local naturalScroll = hs.mouse.scrollDirection().natural
local function norm(delta)
  if not naturalScroll then return delta end
  return { delta[1] * -1, delta[2] * -1 }
end
-- Dragging state
local dragging = false
local dragMoveFrac = 1/20
local dragMoveLargeFrac = dragMoveFrac * 5
-- Mode state
local mode = "normal"
local function setMousePosition(pos)
  if dragging then
    eventtap.event.newMouseEvent(eventtap.event.types.leftMouseDragged, pos):post()
  end
  mouse.absolutePosition(pos)
end
-- Overlay
local overlay = nil
local function createOverlay()
  if overlay then overlay:delete() end
  local currentScr = mouse.getCurrentScreen():frame()
  overlay = canvas.new({
    x = currentScr.x + currentScr.w - 210,
    y = currentScr.y + currentScr.h - 130,
    h = 30, w = 200
  }):appendElements({
    type = "rectangle", action = "fill",
    fillColor = { alpha = 0.4, red = 0, green = 0, blue = 0 },
    roundedRectRadii = { xRadius = 8, yRadius = 8 }
  }, {
    id = "modeText",
    type = "text", text = "-- NORMAL --",
    textSize = 14, textColor = { white = 1 },
    frame = { x = 0, y = 5, h = 30, w = 200 },
    textAlignment = "center"
  })
end
local visualIndicator = nil
local function showVisualIndicator()
  if visualIndicator then return end
  local currentScr = mouse.getCurrentScreen():frame()
  visualIndicator = canvas.new({
    x = currentScr.x + currentScr.w - 210,
    y = currentScr.y + currentScr.h - 90,
    w = 200, h = 30
  }):appendElements({
    type = "rectangle", action = "fill",
    fillColor = { red = 0.2, green = 0.2, blue = 1, alpha = 0.5 },
    roundedRectRadii = { xRadius = 8, yRadius = 8 }
  }, {
    type = "text", text = "-- VISUAL MODE --",
    textSize = 14, textColor = { white = 1 },
    frame = { x = 0, y = 5, h = 30, w = 200 },
    textAlignment = "center"
  })
  visualIndicator:show()
end
local function hideVisualIndicator()
  if visualIndicator then
    visualIndicator:delete()
    visualIndicator = nil
  end
end
function modal:entered()
  createOverlay()
  overlay:show()
end
function modal:exited()
  if overlay then overlay:hide() end
  if mode == "visual" then
    local pos = mouse.absolutePosition()
    if dragging then
      eventtap.event.newMouseEvent(eventtap.event.types.leftMouseUp, pos):post()
      dragging = false
    end
    timer.doAfter(0.05, function() eventtap.leftClick(pos) end)
    mode = "normal"
    hideVisualIndicator()
  end
end
local function bindHoldWithDelay(mod, key, fn, delay, interval)
  modal:bind(mod, key,
    function()
      fn()
      holdTimers[key] = {}
      holdTimers[key].delayTimer = timer.doAfter(delay, function()
        holdTimers[key].repeatTimer = timer.doEvery(interval, fn)
      end)
    end,
    function()
      local t = holdTimers[key]
      if t then
        if t.delayTimer then t.delayTimer:stop() end
        if t.repeatTimer then t.repeatTimer:stop() end
        holdTimers[key] = nil
      end
    end
  )
end
local function moveMouseByFraction(xFrac, yFrac)
  local scr = screen.mainScreen():frame()
  local p = mouse.absolutePosition()
  if mode == "visual" and not dragging then
    dragging = true
    eventtap.event.newMouseEvent(eventtap.event.types.leftMouseDown, p):post()
  end
  setMousePosition({ x = p.x + scr.w * xFrac, y = p.y + scr.h * yFrac })
end
-- Directional movements
local directions = {
  {mod = {}, key = "h", frac = 1/32, dx = -1, dy = 0},
  {mod = {}, key = "l", frac = 1/32, dx = 1, dy = 0},
  {mod = {}, key = "j", frac = 1/32, dx = 0, dy = 1},
  {mod = {}, key = "k", frac = 1/32, dx = 0, dy = -1},
  {mod = {"shift"}, key = "h", frac = 1/8, dx = -1, dy = 0},
  {mod = {"shift"}, key = "l", frac = 1/8, dx = 1, dy = 0},
  {mod = {"shift"}, key = "j", frac = 1/8, dx = 0, dy = 1},
  {mod = {"shift"}, key = "k", frac = 1/8, dx = 0, dy = -1},
}
for _, dir in ipairs(directions) do
  local xFrac, yFrac = dir.dx * dir.frac, dir.dy * dir.frac
  bindHoldWithDelay(dir.mod, dir.key, function() moveMouseByFraction(xFrac, yFrac) end, directionInitialDelay, directionRepeatInterval)
end
local function bindScrollKey(key, initialOffsets, repeatOffsets, initialDragFn, repeatDragFn)
  modal:bind({}, key,
    function()
      if dragging then
        initialDragFn()
      else
        eventtap.scrollWheel(norm(initialOffsets), {}, "pixel")
      end
      holdTimers[key] = {}
      holdTimers[key].delayTimer = timer.doAfter(scrollInitialDelay, function()
        holdTimers[key].repeatTimer = timer.doEvery(scrollRepeatInterval, function()
          if dragging then
            repeatDragFn()
          else
            eventtap.scrollWheel(norm(repeatOffsets), {}, "pixel")
          end
        end)
      end)
    end,
    function()
      local t = holdTimers[key]
      if t then
        if t.delayTimer then t.delayTimer:stop() end
        if t.repeatTimer then t.repeatTimer:stop() end
        holdTimers[key] = nil
      end
    end
  )
end
-- Scroll bindings
bindScrollKey("d", {0, -scrollLargeStep}, {0, -scrollStep},
  function() moveMouseByFraction(0, dragMoveLargeFrac) end,
  function() moveMouseByFraction(0, dragMoveFrac) end)
bindScrollKey("u", {0, scrollLargeStep}, {0, scrollStep},
  function() moveMouseByFraction(0, -dragMoveLargeFrac) end,
  function() moveMouseByFraction(0, -dragMoveFrac) end)
bindScrollKey("w", {-scrollLargeStep, 0}, {-scrollStep, 0},
  function() moveMouseByFraction(mode == "visual" and dragMoveLargeFrac or -dragMoveLargeFrac, 0) end,
  function() moveMouseByFraction(mode == "visual" and dragMoveFrac or -dragMoveFrac, 0) end)
bindScrollKey("b", { scrollLargeStep, 0}, { scrollStep, 0},
  function() moveMouseByFraction(mode == "visual" and -dragMoveLargeFrac or dragMoveLargeFrac, 0) end,
  function() moveMouseByFraction(mode == "visual" and -dragMoveFrac or dragMoveFrac, 0) end)
-- Arrow key bindings: up/down for scrolling (like u/d), left/right for cursor movement (like h/l)
bindScrollKey("down", {0, -scrollLargeStep}, {0, -scrollStep},
  function() moveMouseByFraction(0, dragMoveLargeFrac) end,
  function() moveMouseByFraction(0, dragMoveFrac) end)
bindScrollKey("up", {0, scrollLargeStep}, {0, scrollStep},
  function() moveMouseByFraction(0, -dragMoveLargeFrac) end,
  function() moveMouseByFraction(0, -dragMoveFrac) end)
-- Left/right arrows: move cursor horizontally (same as h/l keys)
local arrowDirections = {
  {key = "left", frac = 1/32, dx = -1, dy = 0},
  {key = "right", frac = 1/32, dx = 1, dy = 0},
}
for _, dir in ipairs(arrowDirections) do
  local xFrac, yFrac = dir.dx * dir.frac, dir.dy * dir.frac
  bindHoldWithDelay({}, dir.key, function() moveMouseByFraction(xFrac, yFrac) end, directionInitialDelay, directionRepeatInterval)
end
local largeScrollStep = scrollStep * 8
local largeScrolls = {
  {mod = {"shift"}, key = "u", delta = {0, largeScrollStep}},
  {mod = {"shift"}, key = "d", delta = {0, -largeScrollStep}},
  {mod = {"shift"}, key = "w", delta = {-largeScrollStep, 0}},
  {mod = {"shift"}, key = "b", delta = {largeScrollStep, 0}},
}
for _, sc in ipairs(largeScrolls) do
  bindHoldWithDelay(sc.mod, sc.key, function()
    eventtap.scrollWheel(norm(sc.delta), {}, "pixel")
  end, scrollInitialDelay, scrollRepeatInterval)
end
-- Medium scroll bindings (Ctrl+U/D) - between normal and large scroll
local mediumScrollStep = scrollStep * 3
local mediumScrolls = {
  {mod = {"ctrl"}, key = "u", delta = {0, mediumScrollStep}},
  {mod = {"ctrl"}, key = "d", delta = {0, -mediumScrollStep}},
}
for _, sc in ipairs(mediumScrolls) do
  bindHoldWithDelay(sc.mod, sc.key, function()
    eventtap.scrollWheel(norm(sc.delta), {}, "pixel")
  end, scrollInitialDelay, scrollRepeatInterval)
end
local function performClicks(count, keepLastDown)
  local pos = mouse.absolutePosition()
  for i = 1, count do
    local down = eventtap.event.newMouseEvent(eventtap.event.types.leftMouseDown, pos)
    down:setProperty(eventtap.event.properties.mouseEventClickState, i)
    down:post()
    if i < count or not keepLastDown then
      local up = eventtap.event.newMouseEvent(eventtap.event.types.leftMouseUp, pos)
      up:post()
    end
  end
end
local function endDragAndClick(pos, action)
  if dragging then
    eventtap.event.newMouseEvent(eventtap.event.types.leftMouseUp, pos):post()
    dragging = false
  end
  if action then
    timer.doAfter(0.05, function()
      eventtap.keyStroke({"cmd"}, action)
      timer.doAfter(0.05, function() eventtap.leftClick(pos) end)
    end)
  else
    timer.doAfter(0.05, function() eventtap.leftClick(pos) end)
  end
end
-- Click bindings
modal:bind({}, "i", function() performClicks(3, false) end)
modal:bind({}, "c", function() eventtap.leftClick(mouse.absolutePosition()) end)
modal:bind({}, "a", function() eventtap.rightClick(mouse.absolutePosition()) end)
-- Visual mode bindings
modal:bind({}, "v", function()
  local pos = mouse.absolutePosition()
  if mode == "visual" then
    endDragAndClick(pos)
    dragging = false
    mode = "normal"
    hideVisualIndicator()
  else
    dragging = true
    eventtap.event.newMouseEvent(eventtap.event.types.leftMouseDown, pos):post()
    mode = "visual"
    showVisualIndicator()
  end
end)
modal:bind({"shift"}, "v", function()
  local pos = mouse.absolutePosition()
  if mode == "visual" then
    endDragAndClick(pos)
    dragging = false
    mode = "normal"
    hideVisualIndicator()
  else
    performClicks(3, true)
    dragging = true
    mode = "visual"
    showVisualIndicator()
  end
end)
modal:bind({}, "y", function()
  if mode == "visual" and dragging then
    endDragAndClick(mouse.absolutePosition(), "c")
    mode = "normal"
    hideVisualIndicator()
  else
    -- Copy selected text or current line when not in visual mode
    hs.eventtap.keyStroke({"cmd"}, "c")
  end
end)
modal:bind({}, "p", function()
  if mode == "visual" and dragging then
    endDragAndClick(mouse.absolutePosition(), "v")
    mode = "normal"
    hideVisualIndicator()
  else
    local pos = mouse.absolutePosition()
    eventtap.leftClick(pos)
    timer.doAfter(0.05, function()
      eventtap.keyStroke({"cmd"}, "v")
      timer.doAfter(0.05, function() modal:exit() end)
    end)
  end
end)
modal:bind({"shift"}, "p", function()
  if mode == "visual" and dragging then
    endDragAndClick(mouse.absolutePosition(), "v")
    mode = "normal"
    hideVisualIndicator()
  else
    local pos = mouse.absolutePosition()
    eventtap.leftClick(pos)
    timer.doAfter(0.05, function()
      eventtap.keyStroke({"cmd"}, "v")
      timer.doAfter(0.05, function() modal:exit() end)
    end)
  end
end)
-- Focus cycle
local function focusAppOffset(offset)
  local wins = window.visibleWindows()
  local cur = window.focusedWindow()
  for idx, w in ipairs(wins) do
    if w:id() == cur:id() then
      local nextWin = wins[(idx + offset - 1) % #wins + 1]
      if nextWin then nextWin:focus() end
      return
    end
  end
end
modal:bind({"shift"}, "a", function() focusAppOffset(1) end)
modal:bind({"shift"}, "i", function() focusAppOffset(-1) end)
modal:bind({"shift"}, "m", function()
  local f = screen.mainScreen():frame()
  setMousePosition({ x = f.x + f.w/2, y = f.y + f.h/2 })
end)
-- Vim-style scroll
local gPending = false
local gTimer = nil
local gDoubleDelay = 0.3
local function scrollToTop()
  eventtap.event.newScrollEvent(norm({0, 1000000}), {}, "pixel"):post()
end
local function scrollToBottom()
  eventtap.event.newScrollEvent(norm({0, -1000000}), {}, "pixel"):post()
end
modal:bind({}, "g", function()
  if gPending then
    if gTimer then gTimer:stop(); gTimer = nil end
    gPending = false
    scrollToTop()
  else
    gPending = true
    gTimer = timer.doAfter(gDoubleDelay, function()
      gPending = false
      gTimer = nil
    end)
  end
end)
modal:bind({"shift"}, "g", function()
  gPending = false
  if gTimer then gTimer:stop(); gTimer = nil end
  scrollToBottom()
end)
local gResetTap = eventtap.new({ eventtap.event.types.keyDown }, function(e)
  if gPending then
    local chars = e:getCharacters() or ""
    if chars:lower() ~= "g" then
      gPending = false
      if gTimer then gTimer:stop(); gTimer = nil end
    end
  end
  return false
end)
gResetTap:start()
-- Modal entry/exit
hs.hotkey.bind({"ctrl","alt","cmd"}, "space", function() modal:enter() end)
hs.hotkey.bind({}, "f12", function() modal:enter() end)
hs.hotkey.bind({"ctrl"}, "=", function() modal:enter() end)
modal:bind({}, "escape", function() modal:exit() end)
modal:bind({"ctrl"}, "c", function() modal:exit() end)
-- Reload config
hs.hotkey.bind({"alt"}, "r", function()
  hs.reload()
  hs.alert("Reloaded")
end)
-- End of configuration.
-- Credit: Artur Grochau – github.com/arturgrochau
