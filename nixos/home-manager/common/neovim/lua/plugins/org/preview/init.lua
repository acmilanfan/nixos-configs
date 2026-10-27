local core = require("plugins.org.core")
local state_mod = require("plugins.org.preview.state")
local block_render = require("plugins.org.preview.render")
local highlights = require("plugins.org.preview.highlights")
local proxy = require("plugins.org.preview.proxy")

local M = {}

local config = {}

local save_options = {
  "number", "relativenumber", "signcolumn", "foldcolumn", "colorcolumn",
  "wrap", "conceallevel", "foldenable", "spell",
}

local function group_name(src)
  return "OrgPreview" .. src
end

-- The source is canonical while it is loaded; an unloaded source buffer still
-- has a name, so read the file from disk instead of rendering an empty preview.
local function source_lines(src)
  if vim.api.nvim_buf_is_loaded(src) then
    return vim.api.nvim_buf_get_lines(src, 0, -1, false)
  end
  local name = vim.api.nvim_buf_get_name(src)
  if name == "" or vim.fn.filereadable(name) == 0 then return {} end
  local ok, lines = pcall(vim.fn.readfile, name)
  return ok and lines or {}
end

local function render_lines(src, win)
  local width = (win and vim.api.nvim_win_is_valid(win)) and vim.api.nvim_win_get_width(win) or 80
  local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(src), ":t")
  return block_render.render(source_lines(src), {
    width = width,
    filename = filename,
  })
end

local function save_window_options(win)
  local options = {}
  for _, name in ipairs(save_options) do
    options[name] = vim.api.nvim_get_option_value(name, { win = win })
  end
  return options
end

local function restore_window_options(win, options)
  if not (win and vim.api.nvim_win_is_valid(win)) then return end
  for _, name in ipairs(save_options) do
    pcall(vim.api.nvim_set_option_value, name, options[name], { win = win })
  end
end

local function apply_preview_options(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then return end
  vim.api.nvim_set_option_value("number", false, { win = win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = win })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = win })
  -- Two blank columns keep the rendered body off the window edge. Folds are
  -- disabled, so the fold column stays empty and shows no markers.
  vim.api.nvim_set_option_value("foldcolumn", "2", { win = win })
  vim.api.nvim_set_option_value("colorcolumn", "", { win = win })
  vim.api.nvim_set_option_value("wrap", false, { win = win })
  vim.api.nvim_set_option_value("conceallevel", 0, { win = win })
  vim.api.nvim_set_option_value("foldenable", false, { win = win })
  vim.api.nvim_set_option_value("spell", false, { win = win })
end

local function set_buffer_options(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  vim.bo[buf].filetype = "org-preview"
end

local function target_line(lines, source_line)
  -- Blank separator lines carry source = 0; skip them when mapping the cursor.
  local earlier
  local later
  for i, line in ipairs(lines) do
    local source = line.source or 0
    if source > 0 then
      if source == source_line then return i end
      if source < source_line then
        earlier = i
      elseif not later then
        later = i
      end
    end
  end
  return earlier or later or 1
end

-- Prefer the rendered line with the same source line and kind (the same
-- rendered segment), then the same segment offset within a wrapped source.
local function locate(lines, source_line, kind, segment)
  if not source_line or source_line <= 0 then return target_line(lines, 0) end
  local matching, any = {}, {}
  for i, line in ipairs(lines) do
    if line.source == source_line then
      any[#any + 1] = i
      if not kind or line.kind == kind then matching[#matching + 1] = i end
    end
  end
  local hits = (#matching > 0) and matching or any
  if #hits > 0 then
    return hits[math.min((segment or 0) + 1, #hits)]
  end
  return target_line(lines, source_line)
end

local function visible(state)
  return state.win and vim.api.nvim_win_is_valid(state.win)
    and vim.api.nvim_win_get_buf(state.win) == state.preview
end

local function wipe_preview(state)
  if vim.api.nvim_buf_is_valid(state.preview) then
    pcall(vim.api.nvim_buf_delete, state.preview, { force = true })
  end
end

-- Return a visible preview to its source window without dropping its buffer,
-- so another preview can be the only visible one and the hidden preview stays
-- reachable through the jumplist.
local function hide(state)
  if not visible(state) then return end
  if not vim.api.nvim_buf_is_valid(state.src) then return end
  vim.api.nvim_win_set_buf(state.win, state.src)
  restore_window_options(state.win, state.options)
  vim.api.nvim_win_call(state.win, function() pcall(vim.fn.winrestview, state.view) end)
end

local function hide_others(keep)
  for _, other in ipairs(state_mod.list()) do
    if other ~= keep then hide(other) end
  end
end

-- Coalesce a burst of source edits, writes, or resizes into one render 50 ms
-- later, matching the debounce in the design. A hidden preview only records
-- the change; entering it renders then.
local function schedule_refresh(state)
  if not state or state.closed then return end
  state.dirty = true
  if state.timer then return end
  state.timer = vim.defer_fn(function()
    state.timer = nil
    if state.closed or state_mod.get(state.src) ~= state then return end
    if not vim.api.nvim_buf_is_valid(state.preview) then return end
    if not visible(state) then return end
    M.refresh(state)
  end, 50)
end

-- Follow the source buffer directly: TextChanged/TextChangedI do not fire for
-- a hidden buffer, but buffer updates do. Lua has no per-callback detach, so a
-- stale watcher returns true on its next event to detach itself; the flag on
-- the state keeps attaching idempotent.
local function watch_source(state)
  if state.watching then return end
  state.watching = true
  local attached = vim.api.nvim_buf_attach(state.src, false, {
    on_lines = function()
      if state.closed or state_mod.get(state.src) ~= state then
        state.watching = false
        return true
      end
      schedule_refresh(state)
      return false
    end,
    -- Reloading the source (:edit, :checktime) does not call on_lines.
    on_reload = function()
      if state.closed or state_mod.get(state.src) ~= state then
        state.watching = false
        return true
      end
      schedule_refresh(state)
      return false
    end,
    on_detach = function() state.watching = false end,
  })
  if not attached then state.watching = false end
end

-- Drop every hook for a preview. The preview buffer and window are the
-- caller's business, because a buffer wipe is one of the cleanup triggers.
local function forget(state)
  state.closed = true
  state.dirty = false
  state.watching = false
  state_mod.remove(state.src)
  pcall(vim.api.nvim_del_augroup_by_name, group_name(state.src))
end

-- Render a stale preview when it becomes visible again.
local function refresh_if_dirty(src)
  local state = state_mod.get(src)
  if not state or not state.dirty then return end
  M.refresh(state)
end

-- Find the link under the preview cursor.
local function link_at_cursor(line)
  return proxy.link_at(line, vim.api.nvim_win_get_cursor(0)[2])
end

-- Toggle a checkbox, open a link, or proxy <CR> to the source. Other lines
-- keep the source mapping authoritative.
local function preview_action(src)
  local state = state_mod.get(src)
  local line = state and state.lines[vim.fn.line(".")]
  if not line then return false end
  -- A link under the cursor wins even on a checkbox line; the checkbox still
  -- toggles when the cursor is on its symbol or elsewhere on the line.
  local link = link_at_cursor(line)
  if link then return proxy.open_link(state, link) end
  if line.checkbox then
    proxy.toggle_checkbox(state, line)
    return true
  end
  return proxy.run(state, "<CR>")
end

local function open_link_at_cursor(src)
  local state = state_mod.get(src)
  local line = state and state.lines[vim.fn.line(".")]
  local link = line and link_at_cursor(line)
  if not link then return false end
  return proxy.open_link(state, link)
end

local function jump_to_source(src)
  local state = state_mod.get(src)
  if not state then return false end
  return proxy.jump(state)
end

local function set_preview_keymaps(src, preview)
  vim.keymap.set("n", "<leader>ov", function() M.toggle(src) end,
    { buffer = preview, nowait = true, desc = "Toggle Org preview" })
  vim.keymap.set("n", "<leader>oj", function() jump_to_source(src) end,
    { buffer = preview, nowait = true, desc = "Jump to Org source" })
  vim.keymap.set("n", "q", function() M.close(src) end,
    { buffer = preview, nowait = true, desc = "Close Org preview" })
  vim.keymap.set("n", "<CR>", function() preview_action(src) end,
    { buffer = preview, nowait = true, desc = "Org preview action" })
  vim.keymap.set("n", "gx", function() open_link_at_cursor(src) end,
    { buffer = preview, nowait = true, desc = "Open Org link" })
end

-- :OrgPreview is context-aware: in a preview it closes that preview, in an Org
-- buffer it toggles, and anywhere else M.toggle warns that no Org file is open.
local function toggle_current()
  local state = state_mod.for_preview(vim.api.nvim_get_current_buf())
  if state then
    M.close(state.src)
    return
  end
  M.toggle(vim.api.nvim_get_current_buf())
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  highlights.setup()
  core.command("OrgPreview", toggle_current, { desc = "Toggle Org preview" })
  -- Global fallback so <leader>ov outside an Org buffer explains itself. The
  -- buffer-local maps installed for Org buffers and previews win over this.
  vim.keymap.set("n", "<leader>ov", function() M.toggle(vim.api.nvim_get_current_buf()) end,
    { nowait = true, desc = "Toggle Org preview" })
end

function M.setup_buffer(buf)
  -- FileType callbacks historically passed 0. Capture a real handle so the
  -- closure and every state key use the buffer the mapping belongs to, not
  -- whatever is current when the mapping is pressed.
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  vim.keymap.set("n", "<leader>ov", function() M.toggle(buf) end,
    { buffer = buf, nowait = true, desc = "Toggle Org preview" })
end

function M.open(src)
  if not vim.api.nvim_buf_is_valid(src) then return nil end
  if vim.bo[src].filetype ~= "org" then
    vim.notify("Open an Org file first", vim.log.levels.WARN)
    return nil
  end
  highlights.setup()

  local existing = state_mod.get(src)
  -- Only one preview may be visible. Hide the others first, keeping their
  -- buffers and state so Ctrl-o still reaches them.
  hide_others(existing)
  if existing and vim.api.nvim_buf_is_valid(existing.preview) then
    local win = existing.win
    if not (win and vim.api.nvim_win_is_valid(win)) then
      win = vim.api.nvim_get_current_win()
      existing.win = win
    end
    apply_preview_options(win)
    vim.api.nvim_win_set_buf(win, existing.preview)
    vim.api.nvim_set_current_win(win)
    set_preview_keymaps(src, existing.preview)
    watch_source(existing)
    proxy.mirror(existing)
    return existing
  elseif existing then
    state_mod.remove(src)
  end

  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= src then
    local source_win = vim.fn.bufwinid(src)
    if source_win ~= -1 then win = source_win end
  end

  local view = vim.api.nvim_win_call(win, function() return vim.fn.winsaveview() end)
  local options = save_window_options(win)
  local source_line = vim.api.nvim_win_get_cursor(win)[1]
  local lines = render_lines(src, win)
  local preview = vim.api.nvim_create_buf(false, true)
  local texts = vim.tbl_map(function(line) return line.text end, lines)
  vim.api.nvim_buf_set_lines(preview, 0, -1, false, texts)
  set_buffer_options(preview)
  highlights.apply(preview, lines)

  local state = {
    src = src,
    preview = preview,
    win = win,
    view = view,
    options = options,
    dirty = false,
    lines = lines,
  }
  state_mod.set(src, state)

  set_preview_keymaps(src, preview)
  proxy.mirror(state)

  local group = vim.api.nvim_create_augroup(group_name(src), { clear = true })
  watch_source(state)
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    buffer = src,
    desc = "Refresh the Org preview after a source write",
    callback = function()
      local current = state_mod.get(src)
      if current then schedule_refresh(current) end
    end,
  })
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
    buffer = src,
    desc = "Follow the Org source again after it is reloaded",
    callback = function()
      local current = state_mod.get(src)
      if not current then return end
      -- :edit! unloads the buffer, which detaches buffer-update callbacks.
      watch_source(current)
      schedule_refresh(current)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = src,
    desc = "Wipe the Org preview with its source",
    callback = function()
      local current = state_mod.get(src)
      if not current then return end
      -- The source is closing, so do not switch the window to it; restore the
      -- options the preview applied before the buffer is replaced.
      if visible(current) then restore_window_options(current.win, current.options) end
      forget(current)
      wipe_preview(current)
    end,
  })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    buffer = preview,
    desc = "Apply the preview window options",
    callback = function()
      local current = state_mod.get(src)
      if not current then return end
      local win = vim.api.nvim_get_current_win()
      if win == current.win then apply_preview_options(win) end
    end,
  })
  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    buffer = preview,
    desc = "Restore the source window options",
    callback = function()
      local current = state_mod.get(src)
      if not current then return end
      local win = vim.api.nvim_get_current_win()
      if win == current.win then restore_window_options(win, current.options) end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    group = group,
    buffer = preview,
    desc = "Render a stale Org preview before it is shown",
    callback = function() refresh_if_dirty(src) end,
  })
  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = group,
    desc = "Re-render the Org preview after a window resize",
    callback = function()
      local current = state_mod.get(src)
      if current then schedule_refresh(current) end
    end,
  })
  -- Deleting the preview buffer must clear the state. An unlisted scratch
  -- buffer unloads on :bdelete, so BufDelete alone never fires for it.
  vim.api.nvim_create_autocmd({ "BufDelete", "BufUnload", "BufWipeout" }, {
    group = group,
    buffer = preview,
    desc = "Clear the Org preview state with its buffer",
    callback = function()
      local current = state_mod.get(src)
      if not current or current.preview ~= preview then return end
      forget(current)
    end,
  })

  apply_preview_options(win)
  vim.api.nvim_win_set_buf(win, preview)
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_cursor(win, { target_line(lines, source_line), 0 })
  return state
end

function M.close(src, opts)
  opts = opts or {}
  local state = state_mod.get(src)
  if not state then return false end

  if visible(state) and vim.api.nvim_buf_is_valid(src) then
    vim.api.nvim_win_set_buf(state.win, src)
    local view = vim.deepcopy(state.view)
    if opts.jump_to then
      local jump = type(opts.jump_to) == "table" and opts.jump_to or { opts.jump_to, 0 }
      view.lnum, view.col = jump[1], jump[2] or 0
    end
    vim.api.nvim_win_call(state.win, function() pcall(vim.fn.winrestview, view) end)
    restore_window_options(state.win, state.options)
    if opts.jump_to then
      local jump = type(opts.jump_to) == "table" and opts.jump_to or { opts.jump_to, 0 }
      pcall(vim.api.nvim_win_set_cursor, state.win, { jump[1], jump[2] or 0 })
    end
  end

  if opts.wipe ~= false then wipe_preview(state) end
  forget(state)
  return true
end

function M.toggle(src)
  local state = state_mod.get(src)
  if state and visible(state) then
    M.close(src)
    return false
  end
  return M.open(src) ~= nil
end

function M.refresh(state)
  if not state or not vim.api.nvim_buf_is_valid(state.preview) then return end
  if not vim.api.nvim_buf_is_valid(state.src) then return end
  -- Keep the cursor on the rendered line for the source row it occupied before
  -- the re-render, and keep its column when the new line is long enough.
  -- Rendered line numbers move when wrapping changes.
  local view, old_row, source, kind, segment
  if visible(state) then
    view = vim.api.nvim_win_call(state.win, function() return vim.fn.winsaveview() end)
    old_row = vim.api.nvim_win_get_cursor(state.win)[1]
    local line = state.lines and state.lines[old_row]
    source = (line and line.source) or 0
    kind = line and line.kind
    if source > 0 and state.lines then
      -- Which wrapped segment of that source line the cursor was on.
      for i, rendered in ipairs(state.lines) do
        if rendered.source == source then
          segment = math.max(old_row - i, 0)
          break
        end
      end
    end
  end

  local lines = render_lines(state.src, state.win)
  local texts = vim.tbl_map(function(line) return line.text end, lines)

  vim.bo[state.preview].modifiable = true
  vim.bo[state.preview].readonly = false
  vim.api.nvim_buf_set_lines(state.preview, 0, -1, false, texts)
  vim.bo[state.preview].modifiable = false
  vim.bo[state.preview].readonly = true
  highlights.apply(state.preview, lines)
  state.lines = lines
  state.dirty = false

  if visible(state) and #lines > 0 then
    local target = locate(lines, source, kind, segment)
    -- A synthetic line (blank separator or fallback title) has no source row;
    -- keep its row instead of jumping to the first content line.
    if (not source or source == 0) and old_row then
      target = math.min(old_row, #lines)
    end
    local text = lines[target] and lines[target].text or ""
    local col = math.min(view and view.col or 0, #text)
    vim.api.nvim_win_call(state.win, function()
      pcall(vim.api.nvim_win_set_cursor, state.win, { target, col })
      local saved = vim.fn.winsaveview()
      local height = vim.api.nvim_win_get_height(state.win)
      -- Restore the topline only when the mapped line stayed inside the old
      -- viewport; otherwise Vim must scroll to keep the cursor visible.
      if view and target >= view.topline and target < view.topline + height then
        saved.topline = view.topline
      end
      saved.lnum, saved.col, saved.curswant = target, col, col
      saved.leftcol = view and view.leftcol or 0
      saved.skipcol = view and view.skipcol or 0
      pcall(vim.fn.winrestview, saved)
    end)
  end
end

function M.is_preview(buf)
  return state_mod.for_preview(buf) ~= nil
end

return M
