-- Highlight groups and extmarks for the rendered Org preview.

local M = {}

M.ns = vim.api.nvim_create_namespace("org-preview")

-- Inline spans and links must win over the whole-line groups (titles,
-- headings, planning lines, code blocks) they are drawn on top of.
local line_priority = 100
local span_priority = 200

local checkbox_symbols = {
  [" "] = "☐",
  ["X"] = "☑",
  ["-"] = "◪",
}

local checkbox_groups = {
  [" "] = "OrgPreviewCheckboxOff",
  ["X"] = "OrgPreviewCheckboxOn",
  ["-"] = "OrgPreviewCheckboxTrans",
}

-- Every group links to an existing Org or theme group, so the preview adds no
-- colorscheme dependency and follows the active theme.
local group_links = {
  { "OrgPreviewTitle", "Title" },
  -- No `#+TITLE` means the filename, which must read as dim fallback text.
  { "OrgPreviewFallbackTitle", "Comment" },
  { "OrgPreviewMetadata", "Comment" },
  { "OrgPreviewTableBorder", "NonText" },
  { "OrgPreviewRule", "NonText" },
  { "OrgPreviewBold", "Bold" },
  { "OrgPreviewItalic", "@markup.italic" },
  { "OrgPreviewUnderline", "@markup.underline" },
  { "OrgPreviewStrike", "@markup.strikethrough" },
  { "OrgPreviewCode", "@markup.raw" },
  { "OrgPreviewVerbatim", "@markup.raw" },
  { "OrgPreviewTodo", "@org.keyword.todo" },
  -- Done keywords and tags are dim, per the design.
  { "OrgPreviewDone", "Comment" },
  { "OrgPreviewTag", "Comment" },
  { "OrgPreviewTimestampActive", "@org.timestamp.active" },
  { "OrgPreviewTimestampInactive", "@org.timestamp.inactive" },
  { "OrgPreviewLink", "@markup.link" },
  { "OrgPreviewCheckboxOff", "@org.checkbox" },
  { "OrgPreviewCheckboxOn", "@org.checkbox.checked" },
  { "OrgPreviewCheckboxTrans", "@org.checkbox.halfchecked" },
}

for level = 1, 6 do
  group_links[#group_links + 1] = {
    "OrgPreviewHeading" .. level,
    "@org.headline.level" .. level,
  }
end

-- Code blocks get a subtle background from the theme's row colors; inline code
-- keeps the lighter OrgPreviewCode group. CursorLine is the preferred source
-- because it is a single-line background that stays subtle in every theme.
local background_candidates = { "CursorLine", "ColorColumn", "Visual" }

local function theme_background()
  for _, name in ipairs(background_candidates) do
    local hl = vim.api.nvim_get_hl(0, { name = name })
    if hl and hl.bg then return hl.bg end
  end
  return nil
end

local function define_code_block()
  local bg = theme_background()
  if bg then
    vim.api.nvim_set_hl(0, "OrgPreviewCodeBlock", { bg = bg, default = true })
  else
    vim.api.nvim_set_hl(0, "OrgPreviewCodeBlock", { link = "CursorLine", default = true })
  end
end

local configured = false

function M.setup()
  if configured then return end
  configured = true
  for _, group in ipairs(group_links) do
    vim.api.nvim_set_hl(0, group[1], { link = group[2], default = true })
  end
  define_code_block()
end

-- The whole-line group for a rendered line, if it has one.
local function line_group(line)
  if line.kind == "heading" then
    return "OrgPreviewHeading" .. math.min(math.max(line.level or 1, 1), 6)
  elseif line.kind == "table" then
    return line.border and "OrgPreviewTableBorder" or nil
  elseif line.kind == "title" then
    return "OrgPreviewTitle"
  elseif line.kind == "fallback-title" then
    return "OrgPreviewFallbackTitle"
  elseif line.kind == "rule" then
    return "OrgPreviewRule"
  elseif line.kind == "meta" or line.kind == "planning" then
    return "OrgPreviewMetadata"
  elseif line.kind == "code" then
    return "OrgPreviewCodeBlock"
  end
  return nil
end

-- The checkbox symbol is the first non-blank text on an item's first line;
-- wrapped continuation lines carry the same metadata but no symbol.
local function checkbox_span(line)
  local checkbox = line.checkbox
  if not checkbox then return nil end
  local symbol = checkbox_symbols[checkbox.state]
  local hl = checkbox_groups[checkbox.state]
  if not (symbol and hl) then return nil end
  local lead = #(line.text:match("^%s*") or "")
  if line.text:sub(lead + 1, lead + #symbol) ~= symbol then return nil end
  return { start_col = lead, end_col = lead + #symbol, hl = hl }
end

local function mark(buf, row, text, start_col, end_col, hl)
  end_col = math.min(end_col, #text)
  if start_col < 0 or end_col <= start_col then return end
  vim.api.nvim_buf_set_extmark(buf, M.ns, row, start_col, {
    end_col = end_col,
    hl_group = hl,
    priority = span_priority,
  })
end

local function mark_line(buf, row, hl)
  vim.api.nvim_buf_set_extmark(buf, M.ns, row, 0, {
    line_hl_group = hl,
    priority = line_priority,
  })
end

function M.apply(buf, lines)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)

  for index, line in ipairs(lines or {}) do
    local row = index - 1
    local whole = line_group(line)
    if whole then mark_line(buf, row, whole) end
    for _, span in ipairs(line.spans or {}) do
      mark(buf, row, line.text, span.start_col, span.end_col, span.hl)
    end
    for _, link in ipairs(line.links or {}) do
      mark(buf, row, line.text, link.start_col, link.end_col, "OrgPreviewLink")
    end
    local checkbox = checkbox_span(line)
    if checkbox then
      mark(buf, row, line.text, checkbox.start_col, checkbox.end_col, checkbox.hl)
    end
  end
end

return M
