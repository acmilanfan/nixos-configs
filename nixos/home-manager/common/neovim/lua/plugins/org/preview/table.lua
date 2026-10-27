local inline = require("plugins.org.preview.inline")

local M = {}

-- Columns are never shrunk below this width; a table that still does not fit
-- is allowed to overflow rather than become unreadable.
local min_width = 8

local alignment_names = { l = "left", r = "right", c = "center" }

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function display_width(text)
  return vim.fn.strdisplaywidth(text)
end

-- Split a line on its pipes, drop the outer empty cells, and record the
-- 0-based byte column where each trimmed cell starts. A missing closing pipe
-- keeps its final cell.
local function split_row(line)
  local pieces = {}
  local pos = 1
  while true do
    local pipe = line:find("|", pos, true)
    local stop = pipe and pipe - 1 or #line
    pieces[#pieces + 1] = { raw = line:sub(pos, stop), pos = pos }
    if not pipe then break end
    pos = pipe + 1
  end

  if #pieces > 0 and trim(pieces[1].raw) == "" then table.remove(pieces, 1) end
  if #pieces > 0 and trim(pieces[#pieces].raw) == "" then table.remove(pieces) end

  local cells = {}
  for _, piece in ipairs(pieces) do
    local lead = #(piece.raw:match("^%s*") or "")
    cells[#cells + 1] = {
      text = trim(piece.raw),
      col = piece.pos - 1 + lead,
    }
  end
  return cells
end

-- A separator row (|---+---|) contains only pipes, dashes, plus signs and
-- spaces, and at least one dash.
local function is_separator(line)
  local body = line:gsub("%s+", "")
  if body:sub(1, 1) ~= "|" or body:sub(-1) ~= "|" then return false end
  if not body:find("-", 1, true) then return false end
  return body:match("^[|%-+]+$") ~= nil
end

-- Org column cookies: <l>, <r>, <c> and <N>, optionally combined (<r8>).
local function cookie(cell)
  local align, digits = cell.text:match("^<([lrc]?)(%d*)>$")
  if not align then return nil end
  if align == "" then align = nil end
  local width = (digits ~= "" and tonumber(digits)) or nil
  if not align and not width then return nil end
  return { align = align and alignment_names[align], width = width }
end

local function is_numeric(text)
  return text:match("^%-?%d[%d.,]*$") ~= nil
end

-- Restrict inline spans/links to a byte range of rendered text and rebase
-- their columns to the start of that range.
local function clip(items, from, to)
  if not items then return {} end
  local out = {}
  for _, item in ipairs(items) do
    local start_col = math.max(item.start_col, from)
    local end_col = math.min(item.end_col, to)
    if end_col > start_col then
      out[#out + 1] = {
        start_col = start_col - from,
        end_col = end_col - from,
        hl = item.hl,
        target = item.target,
        source_col = item.source_col,
      }
    end
  end
  return out
end

-- Split rendered cell text into words, carrying the spans and links that
-- intersect each word.
local function split_words(rendered)
  local words = {}
  local index = 1
  while true do
    local first, last = rendered.text:find("%S+", index)
    if not first then break end
    words[#words + 1] = {
      text = rendered.text:sub(first, last),
      spans = clip(rendered.spans, first - 1, last),
      links = clip(rendered.links, first - 1, last),
    }
    index = last + 1
  end
  return words
end

local function slice_word(word, from, length)
  local to = from + length - 1
  return {
    text = word.text:sub(from, to),
    spans = clip(word.spans, from - 1, to),
    links = clip(word.links, from - 1, to),
  }
end

-- Split a word wider than a cell into display-width chunks. Each chunk
-- records its byte offset in the word so spans can follow it.
local function break_word(word, width)
  local chunks, current, used, start_byte = {}, {}, 0, 1
  for _, char in ipairs(vim.fn.split(word.text, "\\zs")) do
    local char_width = display_width(char)
    if used > 0 and used + char_width > width then
      local text = table.concat(current)
      chunks[#chunks + 1] = { text = text, start_byte = start_byte }
      start_byte = start_byte + #text
      current, used = {}, 0
    end
    current[#current + 1] = char
    used = used + char_width
  end
  if #current > 0 then
    chunks[#chunks + 1] = { text = table.concat(current), start_byte = start_byte }
  end
  return chunks
end

-- Wrap one rendered cell to the column width, keeping inline spans and links
-- at their byte offsets within each output line.
local function wrap_cell(rendered, width)
  local lines = {}
  local current = nil

  local function start_line()
    current = { pieces = {}, used = 0, byte_col = 0, spans = {}, links = {} }
  end

  local function flush()
    if not current then return end
    lines[#lines + 1] = {
      text = table.concat(current.pieces),
      spans = (#current.spans > 0) and current.spans or nil,
      links = (#current.links > 0) and current.links or nil,
    }
    current = nil
  end

  local function append(word, separator)
    if separator then
      current.pieces[#current.pieces + 1] = " "
      current.used = current.used + 1
      current.byte_col = current.byte_col + 1
    end
    local start_col = current.byte_col
    current.pieces[#current.pieces + 1] = word.text
    current.used = current.used + display_width(word.text)
    current.byte_col = current.byte_col + #word.text
    for _, span in ipairs(word.spans) do
      current.spans[#current.spans + 1] = {
        start_col = start_col + span.start_col,
        end_col = start_col + span.end_col,
        hl = span.hl,
      }
    end
    for _, link in ipairs(word.links) do
      current.links[#current.links + 1] = {
        start_col = start_col + link.start_col,
        end_col = start_col + link.end_col,
        target = link.target,
        source_col = link.source_col,
      }
    end
  end

  for _, word in ipairs(split_words(rendered)) do
    local word_width = display_width(word.text)
    if word_width > width then
      flush()
      local chunks = break_word(word, width)
      for index, chunk in ipairs(chunks) do
        start_line()
        append(slice_word(word, chunk.start_byte, #chunk.text), false)
        if index < #chunks then flush() end
      end
    else
      if not current then start_line() end
      if current.used > 0 and current.used + 1 + word_width > width then
        flush()
        start_line()
      end
      append(word, current.used > 0)
    end
  end
  flush()

  if #lines == 0 then
    lines[1] = { text = "" }
  end
  return lines
end

function M.render(rows, opts)
  rows = rows or {}
  opts = opts or {}
  local source_start = opts.source_start or 1
  local indent = opts.indent or 0
  local indent_text = string.rep(" ", indent)

  -- Classify rows: separators and column-cookie rows are not drawn, and the
  -- row directly before the first separator is the header.
  local data, cookies = {}, {}
  local seen_separator = false
  for index, line in ipairs(rows) do
    if is_separator(line) then
      if not seen_separator then
        seen_separator = true
        if #data > 0 then data[#data].header = true end
      end
    else
      local cells = split_row(line)
      local cookie_row, has_cookie, row_cookies = #cells > 0, false, {}
      for column, cell in ipairs(cells) do
        local parsed = cookie(cell)
        if parsed then
          has_cookie = true
          row_cookies[column] = parsed
        elseif cell.text ~= "" then
          cookie_row = false
        end
      end
      if cookie_row and has_cookie then
        for column, parsed in pairs(row_cookies) do
          cookies[column] = cookies[column] or {}
          if parsed.align then cookies[column].align = parsed.align end
          if parsed.width then cookies[column].width = parsed.width end
        end
      else
        data[#data + 1] = { index = index, cells = cells }
      end
    end
  end

  local ncols = 0
  for _, row in ipairs(data) do
    if #row.cells > ncols then ncols = #row.cells end
  end
  if ncols == 0 then return {} end

  -- Natural column widths and inline rendering for every cell.
  local widths = {}
  for column = 1, ncols do widths[column] = 0 end
  for _, row in ipairs(data) do
    row.rendered = {}
    for column, cell in ipairs(row.cells) do
      local rendered = inline.render(cell.text, { source_col = cell.col })
      row.rendered[column] = rendered
      local width = display_width(rendered.text)
      if width > widths[column] then widths[column] = width end
    end
  end

  -- <N> cookies set an exact column width. The shrink loop below may still
  -- reduce them when the exact widths cannot fit.
  for column = 1, ncols do
    local parsed = cookies[column]
    if parsed and parsed.width then
      widths[column] = parsed.width
    end
  end

  local available = (opts.width or math.huge) - indent - (ncols + 1) - 2 * ncols
  local total = 0
  for column = 1, ncols do total = total + widths[column] end
  while total > available do
    local widest, widest_width = nil, min_width
    for column = 1, ncols do
      if widths[column] > widest_width then
        widest, widest_width = column, widths[column]
      end
    end
    if not widest then break end
    -- Shave only the overflow off the widest column, never more than its
    -- slack above the minimum, so a near-fit table keeps using the window.
    local reduction = math.min(total - available, widest_width - min_width)
    widths[widest] = widest_width - reduction
    total = total - reduction
  end

  -- Numeric columns are right-aligned; cookies override the heuristic.
  local aligns = {}
  for column = 1, ncols do
    local parsed = cookies[column]
    if parsed and parsed.align then
      aligns[column] = parsed.align
    else
      local numeric, filled = 0, 0
      for _, row in ipairs(data) do
        local cell = row.cells[column]
        if cell and cell.text ~= "" then
          filled = filled + 1
          if is_numeric(cell.text) then numeric = numeric + 1 end
        end
      end
      aligns[column] = (filled > 0 and numeric * 2 >= filled) and "right" or "left"
    end
  end

  local out = {}
  local function source_of(index)
    return source_start + index - 1
  end

  local function border(left, middle, right, source)
    local pieces = { indent_text, left }
    for column = 1, ncols do
      pieces[#pieces + 1] = string.rep("─", widths[column] + 2)
      pieces[#pieces + 1] = (column < ncols) and middle or right
    end
    out[#out + 1] = { text = table.concat(pieces), source = source, kind = "table", border = true }
  end

  border("┌", "┬", "┐", source_of(data[1].index))

  for position, row in ipairs(data) do
    if position > 1 then
      local rule_source = row.index
      -- The header rule belongs to the first table row, not the hidden
      -- separator line, so jumping from it lands on the header.
      if data[position - 1].header then rule_source = data[1].index end
      border("├", "┼", "┤", source_of(rule_source))
    end

    local wrapped = {}
    local height = 1
    for column = 1, ncols do
      wrapped[column] = wrap_cell(row.rendered[column] or { text = "" }, widths[column])
      if #wrapped[column] > height then height = #wrapped[column] end
    end

    for line_index = 1, height do
      local pieces = { indent_text, "│" }
      local col = #indent_text + #"│"
      local spans, links = {}, {}
      for column = 1, ncols do
        local line = wrapped[column][line_index] or { text = "" }
        local pad = math.max(widths[column] - display_width(line.text), 0)
        local left_pad = 0
        if aligns[column] == "right" then
          left_pad = pad
        elseif aligns[column] == "center" then
          left_pad = math.floor(pad / 2)
        end

        pieces[#pieces + 1] = " "
        col = col + 1
        if left_pad > 0 then
          pieces[#pieces + 1] = string.rep(" ", left_pad)
          col = col + left_pad
        end

        pieces[#pieces + 1] = line.text
        local text_col = col
        if row.header and #line.text > 0 then
          spans[#spans + 1] = {
            start_col = text_col,
            end_col = text_col + #line.text,
            hl = "OrgPreviewBold",
          }
        end
        for _, span in ipairs(line.spans or {}) do
          spans[#spans + 1] = {
            start_col = text_col + span.start_col,
            end_col = text_col + span.end_col,
            hl = span.hl,
          }
        end
        for _, link in ipairs(line.links or {}) do
          links[#links + 1] = {
            start_col = text_col + link.start_col,
            end_col = text_col + link.end_col,
            target = link.target,
            source_col = link.source_col,
          }
        end
        col = text_col + #line.text

        local right_pad = pad - left_pad
        if right_pad > 0 then
          pieces[#pieces + 1] = string.rep(" ", right_pad)
          col = col + right_pad
        end
        pieces[#pieces + 1] = " "
        col = col + 1
        pieces[#pieces + 1] = "│"
        col = col + #"│"
      end

      local rendered = {
        text = table.concat(pieces),
        source = source_of(row.index),
        kind = "table",
        border = false,
      }
      if #spans > 0 then rendered.spans = spans end
      if #links > 0 then rendered.links = links end
      out[#out + 1] = rendered
    end
  end

  border("└", "┴", "┘", source_of(data[#data].index))
  return out
end

return M
