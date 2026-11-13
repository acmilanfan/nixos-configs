-- Markdown block rendering for the read-only preview. Emits the same
-- OrgPreviewLine records as the Org renderer: text, source line, kind, plus
-- inline spans/links, checkbox metadata and heading anchors.

local inline = require("plugins.org.preview.markdown_inline")
local table_render = require("plugins.org.preview.table")

local M = {}

local checkbox_symbols = {
  [" "] = "☐",
  ["X"] = "☑",
  ["-"] = "◪",
}

local function is_blank(line)
  return line:match("^%s*$") ~= nil
end

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function leading_bytes(line)
  return #(line:match("^%s*") or "")
end

local function display_width(text)
  return vim.fn.strdisplaywidth(text)
end

-- Restrict inline spans/links to a byte range of rendered text and rebase
-- their columns to the start of that range.
local function clip_items(items, from, to)
  if not items then return nil end
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
  if #out == 0 then return nil end
  return out
end

local function slice_word(word, from, length)
  local to = from + length - 1
  return {
    text = word.text:sub(from, to),
    source = word.source,
    spans = clip_items(word.spans, from - 1, to),
    links = clip_items(word.links, from - 1, to),
  }
end

-- Split rendered inline text into words, carrying the spans and links that
-- intersect each word.
local function split_inline_words(rendered, source)
  local words = {}
  local index = 1
  while true do
    local first, last = rendered.text:find("%S+", index)
    if not first then break end
    words[#words + 1] = {
      text = rendered.text:sub(first, last),
      source = source,
      spans = clip_items(rendered.spans, first - 1, last),
      links = clip_items(rendered.links, first - 1, last),
    }
    index = last + 1
  end
  return words
end

-- Split a word wider than one output line into display-width chunks. Each
-- chunk records its byte offset in the word so spans can follow it.
local function break_word(word, width)
  local chunks, current, used = {}, {}, 0
  local start_byte = 1
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

-- Lay words out into display lines. Each word carries its source line, inline
-- markup and an optional hard break. The first line uses first_prefix;
-- continuations use next_prefix as a hanging indent.
local function layout(words, opts)
  local width = opts.width or math.huge
  local first_prefix = opts.first_prefix or ""
  local next_prefix = opts.next_prefix or first_prefix
  local first_width = math.max(width - display_width(first_prefix), 1)
  local rest_width = math.max(width - display_width(next_prefix), 1)
  local out = {}
  local current = nil

  local function start_line(prefix, budget, source)
    current = {
      prefix = prefix,
      budget = budget,
      words = {},
      used = 0,
      source = source,
      byte_col = #prefix,
    }
  end

  local function append(word, separator)
    current.byte_col = current.byte_col + separator
    current.words[#current.words + 1] = {
      text = word.text,
      spans = word.spans,
      links = word.links,
      start_col = current.byte_col,
    }
    current.byte_col = current.byte_col + #word.text
  end

  local function flush()
    if current and #current.words > 0 then
      local texts, spans, links = {}, {}, {}
      for _, word in ipairs(current.words) do
        texts[#texts + 1] = word.text
        for _, span in ipairs(word.spans or {}) do
          spans[#spans + 1] = {
            start_col = word.start_col + span.start_col,
            end_col = word.start_col + span.end_col,
            hl = span.hl,
          }
        end
        for _, link in ipairs(word.links or {}) do
          links[#links + 1] = {
            start_col = word.start_col + link.start_col,
            end_col = word.start_col + link.end_col,
            target = link.target,
            source_col = link.source_col,
          }
        end
      end
      local line = {
        text = current.prefix .. table.concat(texts, " "),
        source = current.source,
        kind = opts.kind,
      }
      if #spans > 0 then line.spans = spans end
      if #links > 0 then line.links = links end
      if opts.checkbox then line.checkbox = vim.deepcopy(opts.checkbox) end
      for key, value in pairs(opts.extra or {}) do
        line[key] = value
      end
      out[#out + 1] = line
    end
    current = nil
  end

  for _, word in ipairs(words) do
    if word.break_only then
      flush()
    else
      local word_width = display_width(word.text)
      if not current then
        -- A hard break ends the current line but not the block; the next line
        -- keeps the hanging indent rather than repeating the first prefix
        -- (which may contain a list bullet or checkbox).
        if #out > 0 then
          start_line(next_prefix, rest_width, word.source)
        else
          start_line(first_prefix, first_width, word.source)
        end
      end

      local separator = (#current.words > 0) and 1 or 0
      if #current.words > 0 and current.used + separator + word_width > current.budget then
        flush()
        start_line(next_prefix, rest_width, word.source)
        separator = 0
      end

      if word_width <= current.budget then
        append(word, separator)
        current.used = current.used + separator + word_width
      else
        for index, chunk in ipairs(break_word(word.text, current.budget)) do
          if index > 1 then
            flush()
            start_line(next_prefix, rest_width, word.source)
          end
          local piece = slice_word(word, chunk.start_byte, #chunk.text)
          append(piece, index == 1 and separator or 0)
          current.used = current.used + (index == 1 and separator or 0) + display_width(chunk.text)
        end
      end

      if word.hard then flush() end
    end
  end

  flush()
  return out
end

-- Inline words for one source line. `base_col` is the 0-based byte column
-- where `text` starts in the source so links keep an accurate source column.
-- Two trailing spaces or a trailing backslash mark a hard break.
local function body_words(text, source, base_col)
  local hard = false
  local cleaned = text:gsub("%s+$", "")
  if cleaned:sub(-1) == "\\" then
    hard = true
    cleaned = cleaned:sub(1, -2)
  elseif text:match("  %s*$") then
    hard = true
  end
  local lead = leading_bytes(cleaned)
  local body = trim(cleaned:sub(lead + 1))
  local words = split_inline_words(inline.render(body, { source_col = (base_col or 0) + lead }), source)
  return words, hard
end

local function add_hard_break(words, hard, source)
  if not hard then return end
  if #words > 0 then
    words[#words].hard = true
  else
    words[#words + 1] = { break_only = true, source = source }
  end
end

local function paragraph_words(lines, first, last)
  local words = {}
  for index = first, last do
    local line_words, hard = body_words(lines[index], index, 0)
    for _, word in ipairs(line_words) do words[#words + 1] = word end
    add_hard_break(words, hard, index)
  end
  return words
end

-- Keep letters and digits (including non-ASCII scripts), drop punctuation and
-- symbols. Neovim's charclass reports word characters as 2 and script letters
-- such as CJK above 3; punctuation is 1 and emoji/symbols are 3.
local function slug_char(char)
  if char == " " or char == "\t" then return "-" end
  if char == "-" or char == "_" then return char end
  if char:match("^%w$") then return char:lower() end
  if #char > 1 then
    local ok, class = pcall(vim.fn.charclass, char)
    if not ok then return char:lower() end
    if class == 2 or class > 3 then return char:lower() end
  end
  return nil
end

-- GitHub-style heading slug: lowercase, punctuation removed, whitespace to
-- hyphens, repeated hyphens collapsed. Non-ASCII letters are preserved.
function M.slug(text)
  local pieces = {}
  for char in tostring(text or ""):gmatch(".[\128-\191]*") do
    local piece = slug_char(char)
    if piece then pieces[#pieces + 1] = piece end
  end
  local slug = table.concat(pieces):gsub("%-+", "-")
  return (slug:gsub("^%-+", ""):gsub("%-+$", ""))
end

-- Reserve a deterministic, unique anchor. A heading that collides with an
-- earlier one gets a numeric suffix, GitHub-style.
local function reserve_anchor(text, used)
  local base = M.slug(text)
  local slug = base
  local suffix = 1
  while used[slug] do
    slug = base .. "-" .. suffix
    suffix = suffix + 1
  end
  used[slug] = true
  return slug
end

local function heading(line)
  local indent, hashes, rest = line:match("^(%s*)(#+)(.*)$")
  if not hashes or #hashes > 6 or #indent > 3 then return nil end
  if rest ~= "" and not rest:match("^%s") then return nil end
  local text = rest:match("^%s+(.*)$") or ""
  text = text:gsub("%s+#+%s*$", "")
  text = text:match("^%s*(.-)%s*$")
  -- Closing hashes are not part of the text, so derive the column from where
  -- the trimmed text actually starts rather than from the line length.
  local content_start = #indent + #hashes
  local text_col = content_start
  local found = text ~= "" and line:sub(content_start + 1):find(text, 1, true)
  if found then text_col = content_start + found - 1 end
  return #hashes, text, text_col
end

local function fence_open(line)
  local indent, ticks, info = line:match("^(%s*)(`+)(.*)$")
  if not ticks or #ticks < 3 then return nil end
  return #indent, #ticks, trim(info)
end

local function fence_close(line, count)
  local _, ticks = line:match("^(%s*)(`+)%s*$")
  return ticks ~= nil and #ticks >= count
end

-- Count the leading `>` markers and return the 1-based byte where the quote
-- content starts.
local function quote_prefix(line)
  local pos = 1
  local level = 0
  while true do
    local rest = line:sub(pos)
    local _, stop = rest:find("^%s*>")
    if not stop then break end
    level = level + 1
    pos = pos + stop
    if line:sub(pos, pos) == " " then pos = pos + 1 end
  end
  if level == 0 then return nil end
  return level, pos
end

local function list_item(line)
  local indent, marker, rest = line:match("^(%s*)([-+*])%s+(.*)$")
  if not indent then
    indent, marker, rest = line:match("^(%s*)(%d+[.)])%s+(.*)$")
  end
  if not indent then return nil end
  return #indent, marker, rest
end

local function is_table_row(line)
  return line:match("^%s*|") ~= nil
end

-- Split a Markdown table row on pipes, dropping optional outer pipes and
-- trimming each cell.
local function table_cells(line)
  local text = trim(line)
  if text:sub(1, 1) == "|" then text = text:sub(2) end
  local cells = {}
  local pos = 1
  while true do
    local pipe = text:find("|", pos, true)
    local stop = pipe and pipe - 1 or #text
    cells[#cells + 1] = trim(text:sub(pos, stop))
    if not pipe then break end
    pos = pipe + 1
  end
  if #cells > 1 and cells[#cells] == "" then table.remove(cells) end
  return cells
end

-- Markdown delimiter row: every cell is `:?-+:?`. Returns the per-column
-- alignment overrides and the column count, or nil when the line is not a
-- delimiter.
local function delimiter_row(line)
  local cells = table_cells(line)
  if #cells == 0 then return nil end
  local aligns = {}
  for column = 1, #cells do
    local cell = cells[column]
    if not cell:match("^:?-+:?$") then return nil end
    local left = cell:sub(1, 1) == ":"
    local right = cell:sub(-1) == ":"
    if left and right then
      aligns[column] = "center"
    elseif right then
      aligns[column] = "right"
    elseif left then
      aligns[column] = "left"
    end
  end
  return aligns, #cells
end

-- A table starts when a row with a pipe is directly followed by a delimiter
-- row with the same number of cells. Outer pipes are optional; a table whose
-- header does not start with one renders in bare mode.
local function table_start(lines, index)
  local header = lines[index]
  if not header or not header:find("|", 1, true) then return nil end
  local aligns, ncols = delimiter_row(lines[index + 1] or "")
  if not aligns or #table_cells(header) ~= ncols then return nil end
  return aligns, not header:match("^%s*|")
end

-- Give table.render the outer pipes it expects when the header has them, so a
-- delimiter or body row written without them still reads as a table row. Rows
-- that already have both keep their original indentation for source columns.
local function table_row(line, bare)
  if bare then return line end
  local lead = #(line:match("^%s*") or "")
  local body = line:sub(lead + 1):gsub("%s+$", "")
  if body:sub(1, 1) == "|" and body:sub(-1) == "|" then return line end
  if body:sub(1, 1) ~= "|" then body = "|" .. body end
  if body:sub(-1) ~= "|" then body = body .. "|" end
  return body
end

local function is_rule(line)
  local body = line:gsub("%s+", "")
  if #body < 3 then return false end
  local char = body:sub(1, 1)
  if char ~= "-" and char ~= "*" and char ~= "_" then return false end
  return body:match("^%" .. char .. "+$") ~= nil
end

-- A frontmatter key is a `name:` line. Values and nested keys may follow on
-- the same line or on indented continuation lines.
local function yaml_key(line)
  return line:match("^%s*[%w_%-]+%s*:") ~= nil
end

-- Require the block to look like YAML: at least one key and nothing that is
-- clearly prose. Blank lines, comments, list items and indented continuations
-- are allowed alongside keys.
local function yaml_block(lines, first, last)
  local keyed = false
  for index = first, last do
    local line = lines[index]
    if yaml_key(line) then
      keyed = true
    elseif not (line:match("^%s*$")
      or line:match("^%s*#")
      or line:match("^%s*%-%s")
      or line:match("^%s+%S")) then
      return false
    end
  end
  return keyed
end

-- Frontmatter is only recognized at the very top, only when a closing `---`
-- exists, and only when the inner block looks like YAML; a leading `---` with
-- prose before the next `---` is a horizontal rule, and a later `---` is also
-- a rule.
local function frontmatter(lines)
  if not lines[1] or not lines[1]:match("^%-%-%-%s*$") then return nil end
  for finish = 2, #lines do
    if lines[finish]:match("^%-%-%-%s*$") then
      -- The first `---` closes any frontmatter candidate. When the block is
      -- not YAML, leave the line to the rule renderer instead of hiding it.
      if not yaml_block(lines, 2, finish - 1) then return nil end
      local title, title_source
      for index = 2, finish - 1 do
        local key, value = lines[index]:match("^%s*([%w_%-]+)%s*:%s?(.*)$")
        if key and key:lower() == "title" then
          local parsed = trim(value or "")
          parsed = parsed:match('^"(.*)"$') or parsed:match("^'(.*)'$") or parsed
          parsed = trim(parsed)
          if parsed ~= "" then
            title, title_source = parsed, index
          end
        end
      end
      return { finish = finish, title = title, title_source = title_source }
    end
  end
  return nil
end

-- First ATX H1 outside fenced code, used as the title when frontmatter has
-- none. The caller consumes the line instead of rendering it in the body.
local function first_h1(lines, first)
  local i = first
  while i <= #lines do
    local _, count = fence_open(lines[i])
    if count then
      i = i + 1
      while i <= #lines and not fence_close(lines[i], count) do i = i + 1 end
      i = i + 1
    else
      local level, text, text_col = heading(lines[i])
      if level == 1 and text ~= "" then return i, text, text_col end
      i = i + 1
    end
  end
  return nil
end

local function classify(line)
  if is_blank(line) then return "blank" end
  if heading(line) then return "heading" end
  if fence_open(line) then return "fence" end
  if quote_prefix(line) then return "quote" end
  if is_table_row(line) then return "table" end
  if is_rule(line) then return "rule" end
  if list_item(line) then return "list" end
  return "paragraph"
end

-- A table body row is a pipe-bearing paragraph or piped row; a heading, list,
-- fence, quote or rule ends the table.
local function is_table_body(line)
  local kind = classify(line)
  return (kind == "table" or kind == "paragraph") and line:find("|", 1, true) ~= nil
end

local function render_heading(level, text, text_col, source, width, anchor)
  local indent = string.rep("  ", math.max(level - 1, 0))
  local words = split_inline_words(inline.render(text, { source_col = text_col }), source)
  local rendered = layout(words, {
    width = width,
    first_prefix = indent,
    next_prefix = indent .. "  ",
    kind = "heading",
    extra = { level = math.min(level, 6), anchor = anchor },
  })
  if #rendered == 0 then
    rendered[1] = {
      text = indent,
      source = source,
      kind = "heading",
      level = math.min(level, 6),
      anchor = anchor,
    }
  end
  return rendered
end

local function render_title(text, text_col, source, width, anchor)
  local words = split_inline_words(inline.render(text, { source_col = text_col }), source)
  local rendered = layout(words, {
    width = width,
    first_prefix = "",
    next_prefix = "  ",
    kind = "title",
    extra = { anchor = anchor },
  })
  if #rendered == 0 then
    rendered[1] = { text = "", source = source, kind = "title", anchor = anchor }
  end
  return rendered
end

-- Hide the fence lines. A language label (when present) maps to the opening
-- fence; code lines keep their own source line and lose the fence indent.
local function render_code_block(lines, open_index, close_index, info, prefix)
  local fence_indent = leading_bytes(lines[open_index] or "")
  local out = {}
  local language = trim(info or ""):match("^(%S+)")
  if language then
    out[#out + 1] = {
      text = prefix .. language,
      source = open_index,
      kind = "code",
      spans = {
        { start_col = #prefix, end_col = #prefix + #language, hl = "OrgPreviewMetadata" },
      },
    }
  end
  for index = open_index + 1, close_index - 1 do
    local raw = lines[index] or ""
    local lead = #(raw:match("^ *") or "")
    local dedented = raw:sub(math.min(lead, fence_indent) + 1)
    out[#out + 1] = { text = prefix .. dedented, source = index, kind = "code" }
  end
  return out
end

-- One blockquote line: strip the markers, indent two spaces per nesting level
-- and italicize the content. Long lines reflow with the quote indent.
local function render_quote_line(raw, source, extra_prefix, width)
  local level, content_start = quote_prefix(raw)
  if not level then return nil end
  local prefix = (extra_prefix or "") .. string.rep("  ", level)
  local content = raw:sub(content_start)
  local lead = leading_bytes(content)
  local body = trim(content:sub(lead + 1))
  local col = content_start - 1 + lead
  local words = split_inline_words(inline.render(body, { source_col = col }), source)
  local rendered = layout(words, {
    width = width,
    first_prefix = prefix,
    next_prefix = prefix,
    kind = "paragraph",
  })
  if #rendered == 0 then
    rendered[1] = { text = prefix, source = source, kind = "paragraph" }
  end
  for _, line in ipairs(rendered) do
    if #line.text > #prefix then
      local spans = line.spans or {}
      table.insert(spans, 1, {
        start_col = #prefix,
        end_col = #line.text,
        hl = "OrgPreviewItalic",
      })
      line.spans = spans
    end
  end
  return rendered
end

-- Quote blocks may contain fenced code. Lists inside quotes are best-effort
-- literal text until deeper container support is needed.
local function render_quote_block(lines, first, last, width)
  local out = {}
  local i = first
  while i <= last do
    local level, content_start = quote_prefix(lines[i])
    local content = lines[i]:sub(content_start)
    local open_indent, count, info = fence_open(content)
    if count then
      local close = last + 1
      for j = i + 1, last do
        local _, inner_start = quote_prefix(lines[j])
        if fence_close(lines[j]:sub(inner_start), count) then
          close = j
          break
        end
      end
      local prefix = string.rep("  ", level) .. "  "
      local language = trim(info or ""):match("^(%S+)")
      if language then
        out[#out + 1] = {
          text = prefix .. language,
          source = i,
          kind = "code",
          spans = {
            { start_col = #prefix, end_col = #prefix + #language, hl = "OrgPreviewMetadata" },
          },
        }
      end
      for index = i + 1, close - 1 do
        local _, inner_start = quote_prefix(lines[index])
        local inner = lines[index]:sub(inner_start)
        local lead = #(inner:match("^ *") or "")
        local dedented = inner:sub(math.min(lead, open_indent) + 1)
        out[#out + 1] = { text = prefix .. dedented, source = index, kind = "code" }
      end
      i = close + 1
    else
      for _, rendered in ipairs(render_quote_line(lines[i], i, "", width)) do
        out[#out + 1] = rendered
      end
      i = i + 1
    end
  end
  return out
end

local function render_list_item(lines, item, width)
  local line = lines[item.index]
  local indent, marker, rest = list_item(line)
  local pad = string.rep("  ", item.level or math.floor(indent / 2))
  -- A task marker needs whitespace (or end of line) after `]`, so a link like
  -- `[x](url)` at the start of an item stays a link.
  local state, content = rest:match("^%[([ xX%-])%]%s+(.*)$")
  if not state then
    state = rest:match("^%[([ xX%-])%]%s*$")
    if state then content = "" end
  end
  local checkbox, kind, prefix, content_col
  if state then
    state = (state == " ") and " " or (state == "-" and "-" or "X")
    checkbox = { col = (line:find("[", 1, true) or 1) - 1, state = state }
    kind = "checkbox"
    prefix = pad .. checkbox_symbols[state] .. " "
    content_col = #line - #content
  else
    content = rest
    content_col = #line - #rest
    kind = "list"
    prefix = pad .. (marker:match("^%d") and (marker .. " ") or "• ")
  end

  local hang = string.rep(" ", display_width(prefix))
  local out = {}
  local words = {}
  local first_text = true

  local function flush()
    if #words == 0 then return end
    local with_checkbox = first_text and checkbox or nil
    local rendered = layout(words, {
      width = width,
      first_prefix = first_text and prefix or hang,
      next_prefix = hang,
      kind = kind,
      checkbox = with_checkbox,
    })
    -- The symbol is drawn only on the first line; keeping the checkbox
    -- metadata off wrapped lines prevents a toggle from editing a
    -- continuation line at the symbol's source column.
    for index = 2, #rendered do rendered[index].checkbox = nil end
    for _, output in ipairs(rendered) do out[#out + 1] = output end
    words = {}
    first_text = false
  end

  local initial, hard = body_words(content, item.index, content_col)
  for _, word in ipairs(initial) do words[#words + 1] = word end
  add_hard_break(words, hard, item.index)

  -- A marker-only item still renders its bullet, and keeps it above any
  -- nested code or quote attached to the item.
  if content == "" and #item.parts > 0 then
    flush()
    out[#out + 1] = {
      text = prefix:gsub("%s+$", ""),
      source = item.index,
      kind = kind,
      checkbox = checkbox,
    }
    first_text = false
  end

  for _, part in ipairs(item.parts) do
    if part.type == "text" then
      local part_words, part_hard = body_words(lines[part.index], part.index, 0)
      for _, word in ipairs(part_words) do words[#words + 1] = word end
      add_hard_break(words, part_hard, part.index)
    elseif part.type == "code" then
      flush()
      for _, rendered in ipairs(render_code_block(lines, part.open, part.close, part.info, pad .. "  ")) do
        out[#out + 1] = rendered
      end
      first_text = false
    elseif part.type == "quote" then
      flush()
      for _, rendered in ipairs(render_quote_line(lines[part.index], part.index, pad, width)) do
        out[#out + 1] = rendered
      end
      first_text = false
    end
  end

  flush()

  if #out == 0 then
    out[1] = {
      text = prefix:gsub("%s+$", ""),
      source = item.index,
      kind = kind,
      checkbox = checkbox,
    }
  end
  return out
end

-- Collect a list block, attaching indented continuation text, fenced code and
-- quote lines to the nearest item they sit under. A blank line or a line at
-- the list margin ends the block. Nesting levels come from the item stack, so
-- a two-, three- or four-space child list all render one level deep.
local function collect_list(lines, start)
  local items = {}
  local stack = {}
  local i = start
  while i <= #lines do
    local indent = list_item(lines[i])
    if indent then
      while #stack > 0 and stack[#stack] >= indent do
        table.remove(stack)
      end
      items[#items + 1] = {
        index = i,
        indent = indent,
        level = #stack,
        parts = {},
      }
      stack[#stack + 1] = indent
      i = i + 1
    elseif is_blank(lines[i]) then
      break
    else
      local lead = leading_bytes(lines[i])
      local owner
      for index = #items, 1, -1 do
        if items[index].indent < lead then
          owner = items[index]
          break
        end
      end
      if not owner then break end

      local _, count, info = fence_open(lines[i])
      if count then
        local close = #lines + 1
        for j = i + 1, #lines do
          if fence_close(lines[j], count) then
            close = j
            break
          end
        end
        owner.parts[#owner.parts + 1] = {
          type = "code",
          open = i,
          close = close,
          info = info,
        }
        i = close + 1
      elseif quote_prefix(lines[i]) then
        owner.parts[#owner.parts + 1] = { type = "quote", index = i }
        i = i + 1
      else
        owner.parts[#owner.parts + 1] = { type = "text", index = i }
        i = i + 1
      end
    end
  end
  return items, i
end

function M.render(lines, opts)
  lines = lines or {}
  opts = opts or {}
  local width = opts.width

  local header = frontmatter(lines)
  local body_start = header and (header.finish + 1) or 1

  local title, title_source, title_kind = header and header.title, header and header.title_source, "title"
  local title_col = 0
  local consumed_h1
  if not title then
    local h1, text, text_col = first_h1(lines, body_start)
    if h1 then
      title, title_source, title_col = text, h1, text_col
      consumed_h1 = h1
    end
  end
  if not title and opts.filename and opts.filename ~= "" then
    title, title_source, title_kind = opts.filename, 0, "fallback-title"
  end

  local anchors = {}
  local blocks = {}
  local function begin_block()
    blocks[#blocks + 1] = {}
    return blocks[#blocks]
  end
  local function add(block, rendered)
    block[#block + 1] = rendered
  end

  if title then
    local block = begin_block()
    if title_kind == "fallback-title" then
      add(block, { text = title, source = 0, kind = "fallback-title" })
    else
      -- Only a consumed H1 owns the heading slug. A frontmatter title is
      -- metadata, so it renders without an anchor and a later `# Foo` keeps
      -- `foo` instead of being renumbered to `foo-1`.
      local anchor
      if consumed_h1 then
        anchor = reserve_anchor(inline.render(title, { source_col = title_col }).text, anchors)
      end
      for _, rendered in ipairs(render_title(title, title_col, title_source or 0, width, anchor)) do
        add(block, rendered)
      end
    end
  end

  local i = body_start
  while i <= #lines do
    if i == consumed_h1 then
      i = i + 1
    else
      local line = lines[i]
      local kind = classify(line)
      local table_align, table_bare
      if kind == "table" or kind == "paragraph" then
        table_align, table_bare = table_start(lines, i)
      end

      if kind == "blank" then
        i = i + 1
      elseif table_align ~= nil then
        local block = begin_block()
        local rows = { table_row(line, table_bare), table_row(lines[i + 1], table_bare) }
        local last = i + 1
        while last + 1 <= #lines and is_table_body(lines[last + 1]) do
          last = last + 1
          rows[#rows + 1] = table_row(lines[last], table_bare)
        end
        local rendered = table_render.render(rows, {
          width = width,
          source_start = i,
          inline = inline.render,
          align = table_align,
          bare = table_bare,
        })
        for _, output in ipairs(rendered) do add(block, output) end
        i = last + 1
      elseif kind == "heading" then
        local level, text, text_col = heading(line)
        local plain = inline.render(text, { source_col = text_col }).text
        local anchor = reserve_anchor(plain, anchors)
        local block = begin_block()
        for _, rendered in ipairs(render_heading(level, text, text_col, i, width, anchor)) do
          add(block, rendered)
        end
        i = i + 1
      elseif kind == "fence" then
        local _, count, info = fence_open(line)
        local close = #lines + 1
        for j = i + 1, #lines do
          if fence_close(lines[j], count) then
            close = j
            break
          end
        end
        local block = begin_block()
        for _, rendered in ipairs(render_code_block(lines, i, close, info, "  ")) do
          add(block, rendered)
        end
        i = close + 1
      elseif kind == "quote" then
        local block = begin_block()
        local last = i
        while last + 1 <= #lines and quote_prefix(lines[last + 1]) do
          last = last + 1
        end
        for _, rendered in ipairs(render_quote_block(lines, i, last, width)) do
          add(block, rendered)
        end
        i = last + 1
      elseif kind == "table" then
        -- A piped block without a delimiter row is not a Markdown table; keep
        -- showing its rows literally.
        local block = begin_block()
        while i <= #lines and is_table_row(lines[i]) do
          add(block, { text = trim(lines[i]), source = i, kind = "paragraph" })
          i = i + 1
        end
      elseif kind == "rule" then
        local block = begin_block()
        add(block, {
          text = string.rep("─", math.max(width or 40, 1)),
          source = i,
          kind = "rule",
        })
        i = i + 1
      elseif kind == "list" then
        local block = begin_block()
        local items, next_index = collect_list(lines, i)
        for _, item in ipairs(items) do
          for _, rendered in ipairs(render_list_item(lines, item, width)) do
            add(block, rendered)
          end
        end
        i = next_index
      else
        local block = begin_block()
        local first = i
        while i <= #lines and classify(lines[i]) == "paragraph" do i = i + 1 end
        for _, rendered in ipairs(layout(paragraph_words(lines, first, i - 1), {
          width = width,
          kind = "paragraph",
        })) do
          add(block, rendered)
        end
      end
    end
  end

  local out = {}
  for _, block in ipairs(blocks) do
    if #block > 0 then
      if #out > 0 then
        out[#out + 1] = { text = "", source = 0, kind = "blank" }
      end
      for _, rendered in ipairs(block) do
        out[#out + 1] = rendered
      end
    end
  end
  return out
end

return M
