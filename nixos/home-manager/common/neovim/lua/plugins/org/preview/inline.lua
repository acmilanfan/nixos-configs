local M = {}

local emphasis_hl = {
  ["*"] = "OrgPreviewBold",
  ["/"] = "OrgPreviewItalic",
  ["_"] = "OrgPreviewUnderline",
  ["="] = "OrgPreviewCode",
  ["~"] = "OrgPreviewCode",
  ["+"] = "OrgPreviewStrike",
}

local trailing_url_chars = {
  ["."] = true,
  [","] = true,
  [";"] = true,
  [":"] = true,
  ["!"] = true,
  ["?"] = true,
  [")"] = true,
}

local function is_word(byte)
  return byte ~= "" and byte:match("%w") ~= nil
end

-- Display a target without the `file:` scheme or its `::selector`; the actual
-- target keeps both so the link opener can resolve the anchor.
local function display_target(target)
  local is_file = target:match("^file:") ~= nil
  local display = target:gsub("^file:", "")
  if is_file then
    display = display:gsub("::.*$", "")
  end
  return display
end

local function trim_url(url)
  local trimmed = url
  while #trimmed > 0 and trailing_url_chars[trimmed:sub(-1)] do
    trimmed = trimmed:sub(1, -2)
  end
  return trimmed
end

-- Find a closing marker that ends the emphasis at a word boundary and does
-- not leave leading or trailing whitespace inside the span.
local function emphasis_close(chunk, marker, start)
  local pos = start
  while true do
    local close = chunk:find(marker, pos, true)
    if not close then return nil end
    local content = chunk:sub(start, close - 1)
    local before = chunk:sub(close - 1, close - 1)
    local after = chunk:sub(close + 1, close + 1)
    if content ~= ""
      and not content:match("^%s")
      and not content:match("%s$")
      and before ~= marker
      and after ~= marker
      and not is_word(after) then
      return close, content
    end
    pos = close + 1
  end
end

-- Strip emphasis markers from plain text and return the text plus spans
-- relative to it.
local function render_emphasis(chunk)
  local pieces = {}
  local spans = {}
  local out_len = 0
  local run_start = 1
  local i = 1

  local function flush(upto)
    if upto >= run_start then
      local run = chunk:sub(run_start, upto)
      pieces[#pieces + 1] = run
      out_len = out_len + #run
    end
  end

  while i <= #chunk do
    local marker = chunk:sub(i, i)
    local hl = emphasis_hl[marker]
    local prev = i > 1 and chunk:sub(i - 1, i - 1) or ""
    local after = chunk:sub(i + 1, i + 1)
    if hl and not is_word(prev) and prev ~= marker and after ~= marker then
      local close, content = emphasis_close(chunk, marker, i + 1)
      if close then
        flush(i - 1)
        local start_col = out_len
        pieces[#pieces + 1] = content
        out_len = out_len + #content
        if out_len > start_col then
          spans[#spans + 1] = { start_col = start_col, end_col = out_len, hl = hl }
        end
        i = close + 1
        run_start = i
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  flush(#chunk)
  return table.concat(pieces), spans
end

function M.render(text, opts)
  text = text or ""
  opts = opts or {}
  local base = opts.source_col or 0

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

  local function add_link(value, target, source_col)
    if value == "" then return end
    local start_col = out_len
    emit(value)
    links[#links + 1] = {
      start_col = start_col,
      end_col = out_len,
      target = target,
      source_col = source_col,
    }
  end

  local function emit_plain(chunk)
    local rendered, chunk_spans = render_emphasis(chunk)
    local offset = out_len
    emit(rendered)
    for _, span in ipairs(chunk_spans) do
      spans[#spans + 1] = {
        start_col = offset + span.start_col,
        end_col = offset + span.end_col,
        hl = span.hl,
      }
    end
  end

  local i = 1
  local text_start = 1
  while i <= #text do
    local link
    local start, stop, target, desc = text:find("^%[%[([^%]]+)%]%[([^%]]*)%]%]", i)
    if start then
      link = {
        stop = stop + 1,
        target = target,
        display = (desc ~= "" and desc or display_target(target)),
      }
    else
      start, stop, target = text:find("^%[%[([^%]]+)%]%]", i)
      if start then
        link = { stop = stop + 1, target = target, display = display_target(target) }
      end
    end

    if link then
      emit_plain(text:sub(text_start, i - 1))
      add_link(link.display, link.target, base + i - 1)
      i = link.stop
      text_start = i
    elseif text:sub(i, i) == "<" then
      local _, stop_at, content = text:find("^<(.-)>", i)
      if stop_at then
        emit_plain(text:sub(text_start, i - 1))
        add_span(content, "OrgPreviewTimestampActive")
        i = stop_at + 1
        text_start = i
      else
        i = i + 1
      end
    elseif text:sub(i, i) == "[" then
      local _, stop_at, content = text:find("^%[(%d%d%d%d%-%d%d%-%d%d[^%]]*)%]", i)
      if stop_at then
        emit_plain(text:sub(text_start, i - 1))
        add_span(content, "OrgPreviewTimestampInactive")
        i = stop_at + 1
        text_start = i
      else
        i = i + 1
      end
    elseif text:find("^https?://", i) then
      local _, url_end = text:find("^%S+", i)
      local url = trim_url(text:sub(i, url_end))
      emit_plain(text:sub(text_start, i - 1))
      add_link(url, url, base + i - 1)
      i = i + #url
      text_start = i
    else
      i = i + 1
    end
  end
  emit_plain(text:sub(text_start))

  return { text = table.concat(pieces), spans = spans, links = links }
end

return M
