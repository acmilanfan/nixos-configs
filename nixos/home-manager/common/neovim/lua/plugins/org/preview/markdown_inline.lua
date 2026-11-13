-- Inline Markdown rendering for the preview: strips emphasis and link markup
-- and returns the display text with highlight spans and link ranges.

local M = {}

-- Backslash escapes only apply to ASCII punctuation in Markdown.
local escapable = {}
for ch in ("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"):gmatch(".") do
  escapable[ch] = true
end

local trailing_url_chars = {
  ["."] = true,
  [","] = true,
  [";"] = true,
  [":"] = true,
  ["!"] = true,
  ["?"] = true,
  ["]"] = true,
  ["'"] = true,
  ['"'] = true,
}

local emphasis_markers = {
  { marker = "**", hl = "OrgPreviewBold", boundary = true },
  { marker = "__", hl = "OrgPreviewBold", boundary = true },
  { marker = "~~", hl = "OrgPreviewStrike" },
  { marker = "`", hl = "OrgPreviewCode" },
  { marker = "*", hl = "OrgPreviewItalic", boundary = true },
  { marker = "_", hl = "OrgPreviewItalic", boundary = true },
}

local function is_word(byte)
  return byte ~= "" and byte:match("%w") ~= nil
end

-- Trim trailing prose punctuation from a bare URL. A trailing `)` is only
-- dropped when it is unbalanced, so Wikipedia-style `Foo_(bar)` targets stay
-- intact.
local function trim_url(url)
  local trimmed = url
  while #trimmed > 0 do
    local ch = trimmed:sub(-1)
    if ch == ")" then
      local opens = select(2, trimmed:gsub("%(", ""))
      local closes = select(2, trimmed:gsub("%)", ""))
      if closes <= opens then break end
      trimmed = trimmed:sub(1, -2)
    elseif trailing_url_chars[ch] then
      trimmed = trimmed:sub(1, -2)
    else
      break
    end
  end
  return trimmed
end

-- Remove backslash escapes up front so escaped markers stay literal. `flags`
-- records which output bytes came from an escape, and `src` maps every output
-- byte to its 1-based offset in the original line.
local function unescape(text)
  local bytes, flags, src = {}, {}, {}
  local i = 1
  while i <= #text do
    local ch = text:sub(i, i)
    if ch == "\\" and escapable[text:sub(i + 1, i + 1)] then
      bytes[#bytes + 1] = text:sub(i + 1, i + 1)
      flags[#bytes] = true
      src[#bytes] = i + 1
      i = i + 2
    else
      bytes[#bytes + 1] = ch
      flags[#bytes] = false
      src[#bytes] = i
      i = i + 1
    end
  end
  return table.concat(bytes), flags, src
end

local function find_unescaped(text, flags, needle, from)
  local pos = from
  while true do
    local found = text:find(needle, pos, true)
    if not found then return nil end
    if not flags[found] then return found end
    pos = found + 1
  end
end

-- Return the index just past an optional inline title starting at `from`, or
-- nil when no title starts there. Markdown allows `"title"`, `'title'` and
-- `(title)`; a backslash escapes the next character inside a quoted title.
local function title_end(text, from)
  local opener = text:sub(from, from)
  if opener == '"' or opener == "'" then
    local pos = from + 1
    while pos <= #text do
      local ch = text:sub(pos, pos)
      if ch == "\\" then
        pos = pos + 2
      elseif ch == opener then
        return pos + 1
      else
        pos = pos + 1
      end
    end
    return nil
  end
  if opener == "(" then
    local depth = 1
    local pos = from + 1
    while pos <= #text do
      local ch = text:sub(pos, pos)
      if ch == "(" then
        depth = depth + 1
      elseif ch == ")" then
        depth = depth - 1
        if depth == 0 then return pos + 1 end
      end
      pos = pos + 1
    end
  end
  return nil
end

local function skip_space(text, from)
  local pos = from
  while text:sub(pos, pos):match("%s") do pos = pos + 1 end
  return pos
end

-- Split a plain destination from an optional trailing title. A destination
-- that legitimately contains spaces must use the angle form, so a quoted or
-- parenthesized tail after whitespace is the title, not part of the target.
local function plain_target(body)
  local trimmed = body:match("^%s*(.-)%s*$")
  local target = trimmed:match('^(.-)%s+"[^"]*"$')
    or trimmed:match("^(.-)%s+'[^']*'$")
    or trimmed:match("^(.-)%s+%b()$")
  if target and target ~= "" then return target end
  return trimmed
end

-- Parse a link destination and an optional title. Returns the bare target and
-- the index of the closing `)`, or nil. Plain destinations may contain
-- balanced parentheses; `<>` destinations may contain spaces and end at their
-- `>`, with the title after it. Escaped characters never affect the depth.
local function parse_destination(text, flags, from)
  local first = skip_space(text, from)
  if text:sub(first, first) == "<" then
    local close = find_unescaped(text, flags, ">", first + 1)
    if not close then return nil end
    local pos = skip_space(text, close + 1)
    if text:sub(pos, pos) == ")" then
      return text:sub(first + 1, close - 1), pos
    end
    local titled = title_end(text, pos)
    if not titled then return nil end
    pos = skip_space(text, titled)
    if text:sub(pos, pos) ~= ")" then return nil end
    return text:sub(first + 1, close - 1), pos
  end

  local depth = 1
  local pos = first
  while pos <= #text do
    local ch = text:sub(pos, pos)
    if not flags[pos] then
      if ch == "(" then
        depth = depth + 1
      elseif ch == ")" then
        depth = depth - 1
        if depth == 0 then
          return plain_target(text:sub(first, pos - 1)), pos
        end
      end
    end
    pos = pos + 1
  end
  return nil
end

-- `[text](target)` and `![alt](target)`; the target may be wrapped in angle
-- brackets so it can contain spaces, and either form may carry an inline
-- title that is display metadata, not part of the opened target.
local function parse_link(text, flags, start, image)
  local label_start = start + (image and 2 or 1)
  local label_end = find_unescaped(text, flags, "]", label_start)
  if not label_end then return nil end
  if text:sub(label_end + 1, label_end + 1) ~= "(" then return nil end
  local target, target_end = parse_destination(text, flags, label_end + 2)
  if not target then return nil end
  target = target:match("^%s*(.-)%s*$")
  if target == "" then return nil end
  local label = text:sub(label_start, label_end - 1)
  if image then
    label = label ~= "" and ("image: " .. label) or "image"
  end
  return { start = start, stop = target_end + 1, label = label, target = target }
end

-- Find a closing marker that is not escaped, does not leave leading or
-- trailing whitespace inside the span, and ends on a word boundary when the
-- marker must not sit inside a word.
local function emphasis_close(text, flags, marker, from, boundary)
  local pos = from
  while true do
    local close = find_unescaped(text, flags, marker, pos)
    if not close then return nil end
    local content = text:sub(from, close - 1)
    local after = text:sub(close + #marker, close + #marker)
    if content ~= ""
      and not content:match("^%s")
      and not content:match("%s$")
      and not (boundary and is_word(after)) then
      return close, content
    end
    pos = close + 1
  end
end

function M.render(text, opts)
  text = text or ""
  opts = opts or {}
  local base = opts.source_col or 0

  local clean, flags, src = unescape(text)
  local pieces, spans, links = {}, {}, {}
  local out_len = 0

  local function emit(value)
    if value ~= "" then
      pieces[#pieces + 1] = value
      out_len = out_len + #value
    end
  end

  local function add_span(value, hl)
    if value == "" then return end
    local start_col = out_len
    emit(value)
    spans[#spans + 1] = { start_col = start_col, end_col = out_len, hl = hl }
  end

  local function add_link(value, target, at)
    if value == "" then return end
    local start_col = out_len
    emit(value)
    links[#links + 1] = {
      start_col = start_col,
      end_col = out_len,
      target = target,
      source_col = base + src[at] - 1,
    }
  end

  local plain_start = 1

  local function flush(upto)
    if upto >= plain_start then emit(clean:sub(plain_start, upto)) end
  end

  local i = 1
  while i <= #clean do
    local ch = clean:sub(i, i)
    local handled = false

    if not flags[i] then
      local link
      if ch == "!" and clean:sub(i + 1, i + 1) == "[" then
        link = parse_link(clean, flags, i, true)
      elseif ch == "[" then
        link = parse_link(clean, flags, i, false)
      elseif ch == "<" then
        local close = find_unescaped(clean, flags, ">", i + 1)
        if close then
          local content = clean:sub(i + 1, close - 1)
          if content:match("^https?://%S+$") then
            link = { start = i, stop = close + 1, label = content, target = content }
          end
        end
      elseif (clean:sub(i, i + 7) == "https://" or clean:sub(i, i + 6) == "http://")
        and not is_word(clean:sub(i - 1, i - 1)) then
        local stop = clean:find("%s", i) or #clean + 1
        local url = trim_url(clean:sub(i, stop - 1))
        link = { start = i, stop = i + #url, label = url, target = url }
      end

      if link then
        flush(i - 1)
        add_link(link.label, link.target, link.start)
        i = link.stop
        plain_start = i
        handled = true
      end

      if not handled then
        for _, spec in ipairs(emphasis_markers) do
          local marker = spec.marker
          if clean:sub(i, i + #marker - 1) == marker then
            local prev = clean:sub(i - 1, i - 1)
            local after = clean:sub(i + #marker, i + #marker)
            local single = #marker == 1 and (marker == "*" or marker == "_")
            local opens = after ~= ""
              and not after:match("%s")
              and not (spec.boundary and is_word(prev))
              and not (single and after == marker)
            if opens then
              local close, content = emphasis_close(clean, flags, marker, i + #marker, spec.boundary)
              if close then
                flush(i - 1)
                add_span(content, spec.hl)
                i = close + #marker
                plain_start = i
                handled = true
                break
              end
            end
          end
        end
      end
    end

    if not handled then
      i = i + 1
    end
  end

  flush(#clean)

  return { text = table.concat(pieces), spans = spans, links = links }
end

return M
