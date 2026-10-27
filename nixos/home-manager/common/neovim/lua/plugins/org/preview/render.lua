local inline = require("plugins.org.preview.inline")
local table_render = require("plugins.org.preview.table")

local M = {}

local function is_blank(line)
  return line:match("^%s*$") ~= nil
end

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function directive(line)
  local name, value = line:match("^%s*#%+([%w_%-]+):%s?(.*)$")
  if not name then return nil end
  return name:upper(), trim(value)
end

local function block_begin(line)
  local name, rest = line:upper():match("^%s*#%+BEGIN_([%w_]+)(.*)$")
  if not name then return nil end
  if rest ~= "" and not rest:match("^%s") then return nil end
  -- Arguments keep their original case, e.g. the `lua` in `#+BEGIN_SRC lua`.
  local args = trim(line:sub(#line - #rest + 1))
  return name, args
end

local function block_end(line, name)
  return line:upper():match("^%s*#%+END_" .. name .. "%s*$") ~= nil
end

local function any_block_end(line)
  return line:upper():match("^%s*#%+END_[%w_]+%s*$") ~= nil
end

local function drawer_start(line)
  local name = line:match("^%s*:([%w_%-]+):%s*$")
  if not name or name:upper() == "END" then return nil end
  return name:upper()
end

local function drawer_end(line)
  return line:upper():match("^%s*:END:%s*$") ~= nil
end

local function is_comment(line)
  return line:match("^%s*#%s") ~= nil or line:match("^%s*#%s*$") ~= nil
end

local function heading(line)
  local stars, text = line:match("^(%*+)%s+(.*)$")
  if not stars then return nil end
  return #stars, text
end

local planning_labels = {
  SCHEDULED = "Scheduled",
  DEADLINE = "Deadline",
}

-- Parse every planning keyword on a line. A combined
-- `SCHEDULED: <...> DEADLINE: <...>` line renders one dim line per keyword;
-- CLOSED stays hidden.
local function planning(line)
  local lead = #(line:match("^%s*") or "")
  local text = line:sub(lead + 1)
  if not (text:match("^SCHEDULED:") or text:match("^DEADLINE:")) then return nil end

  local parts = {}
  local pos = 1
  while pos <= #text do
    local keyword, value_start = text:match("^(%u+):%s*()", pos)
    if not keyword or not (planning_labels[keyword] or keyword == "CLOSED") then break end
    local next_pos = #text + 1
    for other in pairs(planning_labels) do
      local start = text:find(other .. ":", value_start, true)
      if start and start < next_pos then next_pos = start end
    end
    local closed = text:find("CLOSED:", value_start, true)
    if closed and closed < next_pos then next_pos = closed end

    local value = trim(text:sub(value_start, next_pos - 1))
    if planning_labels[keyword] and value ~= "" then
      value = value:match("^<(.+)>$") or value:match("^%[(.+)%]$") or value
      parts[#parts + 1] = planning_labels[keyword] .. " " .. value
    end
    pos = next_pos
  end
  if #parts == 0 then return nil end
  return parts
end

local function is_closed(line)
  return line:match("^%s*CLOSED:%s*") ~= nil
end

local function is_table(line)
  return line:match("^%s*|") ~= nil
end

local function list_item(line)
  local indent, marker, rest = line:match("^(%s*)([-+*])%s+(.*)$")
  if not indent then
    indent, marker, rest = line:match("^(%s*)(%d+[.)])%s+(.*)$")
  end
  if not indent then return nil end
  return indent, marker, rest
end

local function is_list(line)
  return list_item(line) ~= nil
end

-- Single source of truth for how each source line is treated. The dispatch
-- loop and the paragraph collector both use it, so block boundaries cannot
-- drift apart.
local function classify(line)
  if is_blank(line) then return "blank" end
  if block_begin(line) then return "begin" end
  if directive(line) then return "directive" end
  if drawer_start(line) then return "drawer" end
  if is_comment(line) then return "comment" end
  if drawer_end(line) or is_closed(line) or any_block_end(line) then return "hidden" end
  if heading(line) then return "heading" end
  if planning(line) then return "planning" end
  if is_table(line) then return "table" end
  if is_list(line) then return "list" end
  return "paragraph"
end

local checkbox_symbols = {
  [" "] = "☐",
  ["X"] = "☑",
  ["-"] = "◪",
}

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
  for _, char in ipairs(vim.fn.split(word, "\\zs")) do
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
-- markup, and an optional hard break. The first line uses first_prefix;
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
      out[#out + 1] = line
    end
    current = nil
  end

  for _, word in ipairs(words) do
    if word.break_only then
      flush()
    else
      local word_width = display_width(word.text)
      if not current then start_line(first_prefix, first_width, word.source) end

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

local function paragraph_words(lines, first, last)
  local words = {}
  for index = first, last do
    local raw = lines[index]
    local hard = raw:match("\\\\%s*$") ~= nil
    local text = hard and (raw:gsub("\\\\%s*$", "")) or raw
    local lead = #(text:match("^%s*") or "")
    local body = trim(text:sub(lead + 1))
    local line_words = split_inline_words(inline.render(body, { source_col = lead }), index)
    for _, word in ipairs(line_words) do
      words[#words + 1] = word
    end
    if hard then
      if #line_words > 0 then
        words[#words].hard = true
      else
        words[#words + 1] = { break_only = true, source = index }
      end
    end
  end
  return words
end

local function leading_width(line)
  return #(line:match("^%s*") or "")
end

-- Render a list item plus any indented continuation lines absorbed into it.
-- Continuation lines keep their own source line and reflow behind the item's
-- hanging indent.
local function render_list_item(lines, index, width, continuations)
  local line = lines[index]
  local indent, marker, rest = list_item(line)
  local pad = string.rep("  ", math.floor(#indent / 2))
  local state, content = rest:match("^%[([ X%-])%]%s+(.*)$")
  if not state then
    -- A freshly added checkbox may have no body text yet.
    state = rest:match("^%[([ X%-])%]%s*$")
    if state then content = "" end
  end
  local prefix, kind, checkbox, content_col
  if state then
    prefix = pad .. checkbox_symbols[state] .. " "
    kind = "checkbox"
    checkbox = { col = (line:find("[", 1, true) or 1) - 1, state = state }
    content_col = #line - #content
  else
    local ordered = marker:match("^%d")
    prefix = pad .. (ordered and (marker:gsub("[.)]", "") .. ". ") or "• ")
    kind = "list"
    content = rest
    content_col = #line - #rest
  end

  local words = split_inline_words(inline.render(content, { source_col = content_col }), index)
  for _, extra_index in ipairs(continuations or {}) do
    local raw = lines[extra_index]
    local lead = leading_width(raw)
    local body = trim(raw:sub(lead + 1))
    for _, word in ipairs(split_inline_words(inline.render(body, { source_col = lead }), extra_index)) do
      words[#words + 1] = word
    end
  end

  local rendered = layout(words, {
    width = width,
    first_prefix = prefix,
    next_prefix = string.rep(" ", display_width(prefix)),
    kind = kind,
    checkbox = checkbox,
  })
  if #rendered == 0 then
    rendered[1] = {
      text = (prefix:gsub("%s+$", "")),
      source = index,
      kind = kind,
      checkbox = checkbox,
    }
  end
  return rendered
end

local fallback_keywords = {
  TODO = "TODO",
  DOING = "TODO",
  HOLD = "TODO",
  IDEA = "TODO",
  NOTE = "TODO",
  DONE = "DONE",
}

-- Keyword -> type ("TODO" or "DONE") from the active Org config, so configured
-- keywords such as SKIP are recognized and dimmed. Falls back to the common
-- default set when the config is unavailable.
local function todo_keywords()
  local ok, keywords = pcall(function()
    return require("orgmode.config"):get_todo_keywords():all()
  end)
  if ok and type(keywords) == "table" then
    local out = {}
    for _, keyword in ipairs(keywords) do
      if keyword.value then out[keyword.value] = keyword.type end
    end
    if next(out) then return out end
  end
  return fallback_keywords
end

-- Render a heading title through the inline parser, keeping the TODO keyword
-- and trailing tags as their own highlighted pieces. Long headings wrap with
-- a hanging indent aligned after the keyword.
local function render_heading(line, level, text, source, width, keywords)
  local title = text
  local keyword, rest = title:match("^(%u+)%s+(.*)$")
  if keyword and keywords[keyword] then
    title = rest
  elseif keywords[title] then
    keyword, title = title, ""
  else
    keyword = nil
  end

  local body, tags = title:match("^(.-)%s+(:[^%s]+:)%s*$")
  if not body then
    local only = title:match("^(:[^%s]+:)%s*$")
    if only then
      body, tags = "", only
    end
  end
  if not tags then body = title end

  local title_col = (#line - #text) + (#text - #title)
  local indent = string.rep("  ", math.max(level - 1, 0))

  local words = {}
  if keyword then
    words[#words + 1] = {
      text = keyword,
      source = source,
      spans = {
        {
          start_col = 0,
          end_col = #keyword,
          hl = (keywords[keyword] == "DONE") and "OrgPreviewDone" or "OrgPreviewTodo",
        },
      },
    }
  end
  for _, word in ipairs(split_inline_words(inline.render(body, { source_col = title_col }), source)) do
    words[#words + 1] = word
  end
  if tags then
    words[#words + 1] = {
      text = tags,
      source = source,
      spans = { { start_col = 0, end_col = #tags, hl = "OrgPreviewTag" } },
    }
  end

  local rendered = layout(words, {
    width = width,
    first_prefix = indent,
    next_prefix = indent .. string.rep(" ", keyword and (#keyword + 1) or 0),
    kind = "heading",
  })
  if #rendered == 0 then
    rendered[1] = { text = indent, source = source, kind = "heading" }
  end
  for _, out in ipairs(rendered) do
    out.level = math.min(level, 6)
  end
  return rendered
end

function M.render(lines, opts)
  lines = lines or {}
  opts = opts or {}

  local n = #lines
  local blocks = {}
  local current = nil
  local title_seen = false
  -- Resolve once per render so every heading shares the same keyword set.
  local keywords = todo_keywords()

  local function begin_block()
    current = {}
    blocks[#blocks + 1] = current
    return current
  end

  local function add(line)
    if not current then begin_block() end
    current[#current + 1] = line
  end

  local function parse_header(start)
    local title, meta, meta_source
    local i = start
    while i <= n do
      if is_blank(lines[i]) then
        i = i + 1
      else
        local name, value = directive(lines[i])
        if not name then break end
        if name == "TITLE" then
          if value ~= "" then
            title = { text = value, source = i, kind = "title" }
            title_seen = true
          end
        elseif name == "AUTHOR" or name == "DATE" then
          if value ~= "" then
            meta = meta or {}
            meta[#meta + 1] = value
            meta_source = meta_source or i
          end
        end
        i = i + 1
      end
    end

    if title or meta then
      current = nil
      begin_block()
      if title then add(title) end
      if meta then
        add({ text = table.concat(meta, " · "), source = meta_source or 0, kind = "meta" })
      end
    end
    current = nil
    return i
  end

  local i = 1
  while i <= n do
    local line = lines[i]
    local kind = classify(line)

    if kind == "blank" then
      current = nil
      i = i + 1
    elseif kind == "begin" then
      local begin_name, begin_args = block_begin(line)
      local content_start, content_end
      if begin_name == "SRC" or begin_name == "EXAMPLE" or begin_name == "QUOTE" then
        content_start = i + 1
        content_end = content_start
        while content_end <= n and not block_end(lines[content_end], begin_name) do
          content_end = content_end + 1
        end
        content_end = content_end - 1
        current = nil
        begin_block()
        -- The language label is dim and maps to the block's opening fence, so
        -- jump-to-source lands on `#+BEGIN_SRC`.
        local language = begin_name == "SRC" and begin_args:match("^(%S+)") or nil
        if language then
          local label = "  " .. language
          add({
            text = label,
            source = i,
            kind = "code",
            spans = { { start_col = 2, end_col = #label, hl = "OrgPreviewMetadata" } },
          })
        end
        for content = content_start, content_end do
          if begin_name == "QUOTE" then
            local text = "  " .. lines[content]
            add({
              text = text,
              source = content,
              kind = "paragraph",
              spans = (#text > 2)
                and { { start_col = 2, end_col = #text, hl = "OrgPreviewItalic" } }
                or nil,
            })
          else
            add({ text = "  " .. lines[content], source = content, kind = "code" })
          end
        end
        current = nil
        i = (content_end < n) and (content_end + 2) or (n + 1)
      else
        current = nil
        i = i + 1
      end
    elseif kind == "directive" then
      local name = directive(line)
      if name == "TITLE" or name == "AUTHOR" or name == "DATE" then
        i = parse_header(i)
      else
        current = nil
        i = i + 1
      end
    elseif kind == "drawer" then
      current = nil
      i = i + 1
      while i <= n and not drawer_end(lines[i]) do i = i + 1 end
      if i <= n then i = i + 1 end
    elseif kind == "comment" or kind == "hidden" then
      current = nil
      i = i + 1
    elseif kind == "heading" then
      local level, text = heading(line)
      current = nil
      local block = begin_block()
      -- Level-1 headings get an extra blank line above, except at the very top
      -- of the document.
      if level == 1 then block.extra_above = true end
      for _, rendered in ipairs(render_heading(line, level, text, i, opts.width, keywords)) do
        add(rendered)
      end
      if level == 1 then
        add({
          text = string.rep("─", math.max(opts.width or 40, 1)),
          source = i,
          kind = "rule",
        })
      end
      i = i + 1
      while i <= n do
        local parts = planning(lines[i])
        if not parts then break end
        for _, part in ipairs(parts) do
          add({ text = part, source = i, kind = "planning" })
        end
        i = i + 1
      end
      current = nil
    elseif kind == "planning" then
      current = nil
      begin_block()
      for _, part in ipairs(planning(line)) do
        add({ text = part, source = i, kind = "planning" })
      end
      current = nil
      i = i + 1
    elseif kind == "table" then
      current = nil
      begin_block()
      local first = i
      local rows = {}
      while i <= n and classify(lines[i]) == "table" do
        rows[#rows + 1] = lines[i]
        i = i + 1
      end
      for _, rendered in ipairs(table_render.render(rows, {
        width = opts.width,
        source_start = first,
      })) do
        add(rendered)
      end
      current = nil
    elseif kind == "list" then
      current = nil
      begin_block()
      -- Collect the whole list, attaching indented continuation paragraphs to
      -- the nearest item they sit under. Reflow reuses that item's prefix and
      -- hanging indent; a line at the list's margin ends the block.
      local items = {}
      while i <= n do
        local item_kind = classify(lines[i])
        if item_kind == "list" then
          items[#items + 1] = { index = i, indent = leading_width(lines[i]), extras = {} }
          i = i + 1
        elseif item_kind == "paragraph" and #items > 0 then
          local lead = leading_width(lines[i])
          local owner
          for k = #items, 1, -1 do
            if items[k].indent < lead then
              owner = items[k]
              break
            end
          end
          if not owner then break end
          owner.extras[#owner.extras + 1] = i
          i = i + 1
        else
          break
        end
      end
      for _, item in ipairs(items) do
        for _, rendered in ipairs(render_list_item(lines, item.index, opts.width, item.extras)) do
          add(rendered)
        end
      end
      current = nil
    else
      current = nil
      begin_block()
      local first = i
      while i <= n and classify(lines[i]) == "paragraph" do i = i + 1 end
      for _, rendered in ipairs(layout(paragraph_words(lines, first, i - 1), {
        width = opts.width,
        kind = "paragraph",
      })) do
        add(rendered)
      end
      current = nil
    end
  end

  if not title_seen and opts.filename and opts.filename ~= "" then
    local fallback = { text = opts.filename, source = 0, kind = "fallback-title" }
    local first = blocks[1]
    if first and first[1] and first[1].kind == "meta" then
      table.insert(first, 1, fallback)
    else
      table.insert(blocks, 1, { fallback })
    end
  end

  local out = {}
  for _, block in ipairs(blocks) do
    if #block > 0 then
      if #out > 0 then
        out[#out + 1] = { text = "", source = 0, kind = "blank" }
        if block.extra_above then
          out[#out + 1] = { text = "", source = 0, kind = "blank" }
        end
      end
      for _, rendered in ipairs(block) do
        out[#out + 1] = rendered
      end
    end
  end
  return out
end

return M
