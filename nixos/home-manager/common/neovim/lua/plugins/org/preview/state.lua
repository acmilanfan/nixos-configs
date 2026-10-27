local M = {}

local by_source = {}

function M.get(src)
  return by_source[src]
end

function M.set(src, state)
  by_source[src] = state
end

function M.remove(src)
  by_source[src] = nil
end

function M.for_preview(buf)
  for _, state in pairs(by_source) do
    if state.preview == buf then return state end
  end
  return nil
end

-- Snapshot of every live preview, safe to iterate while a caller manipulates
-- windows or state.
function M.list()
  local states = {}
  for _, state in pairs(by_source) do
    states[#states + 1] = state
  end
  return states
end

return M
