local ax = dofile(vimModeScriptPath .. "lib/axuielement.lua")

local registeredPids = {}

local function createApplicationWatcher(application, vim)
  if not application then return nil end

  local pid = application:pid()
  local observer

  local function tryCreate(app)
    if registeredPids[pid] then return end

    observer = ax.observer.new(app:pid())

    observer
      :callback(function() vim:exit() end)
      :addWatcher(
        ax.applicationElement(app),
        "AXFocusedUIElementChanged"
      )
      :start()

    registeredPids[pid] = observer
  end

  local attempts = 0
  local maxAttempts = 3

  local function attemptCreate()
    attempts = attempts + 1

    local app = hs.application.applicationForPID(pid)
    if not app then
      registeredPids[pid] = nil
      return
    end

    local status, error = pcall(tryCreate, app)

    if status then return end

    registeredPids[pid] = nil

    if attempts < maxAttempts then
      hs.timer.doAfter(0.15 * attempts, attemptCreate)
    else
      vimLogger.d(
        "Could not start watcher for PID: " .. pid ..
          " and name: " .. app:name()
      )
      vimLogger.d("Error: " .. hs.inspect.inspect(error))
    end
  end

  attemptCreate()

  return observer
end

-- When someone focuses out of a field, we want to exit Vim mode.
local function createFocusWatcher(vim)
  createApplicationWatcher(hs.application.frontmostApplication(), vim)

  local watcher = hs.application.watcher.new(function(_, eventType, application)
    if eventType == hs.application.watcher.activated then
      createApplicationWatcher(application, vim)
    end
  end)

  watcher:start()

  return watcher
end

return createFocusWatcher
