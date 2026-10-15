local core = require("plugins.org.core")
local M = {}

-- ── YouTube helpers ─────────────────────────────────────────────

-- Helper: Query Matcher
local function matches_query(headline, query)
  if query == "" then
    return true
  end
  local conditions = vim.split(query, "+", { plain = true })
  for _, cond in ipairs(conditions) do
    local key, op, val = cond:match("^([%w_-]+)([<>=]+)(.+)$")
    if key then
      local prop_val = headline:get_property(key)
      if not prop_val then
        return false
      end
      local n_prop, n_val = tonumber(prop_val), tonumber(val)
      if n_prop and n_val then
        if op == "<" and not (n_prop < n_val) then
          return false
        end
        if op == ">" and not (n_prop > n_val) then
          return false
        end
        if op == "=" and not (n_prop == n_val) then
          return false
        end
        if op == "<=" and not (n_prop <= n_val) then
          return false
        end
        if op == ">=" and not (n_prop >= n_val) then
          return false
        end
      elseif op == "=" and prop_val ~= val then
        return false
      end
    end
  end
  return true
end

-- Helper: Parse Date
local function parse_date(date_str)
  if not date_str then
    return 0
  end
  local Y, M, D, h, m, s = date_str:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not Y then
    return 0
  end
  return os.time({ year = Y, month = M, day = D, hour = h, min = m, sec = s })
end

local function youtube_dir()
  return core.root() .. "/consume/youtube"
end

-- Open = any not-done keyword (TODO/DOING/HOLD/...), matching orgmode's own todo_type.
local function open_keyword(keyword)
  local found = require("orgmode.config"):get_todo_keywords():find(keyword)
  return found ~= nil and found.type == "TODO"
end

-- Invalidated on :OrgYoutubeReload and on writes under youtube_dir(); the TTL
-- only catches edits made outside Neovim (sync, scripts).
local _cached_youtube_items = nil
local _cache_time = 0

local function get_all_youtube_items(force_reload)
  local now = os.time()
  if not force_reload and _cached_youtube_items and (now - _cache_time < 300) then
    return _cached_youtube_items
  end

  local yt_paths = vim.fn.glob(youtube_dir() .. "/*.org", false, true)
  local items = {}

  for _, path in ipairs(yt_paths) do
    local ok, lines = pcall(vim.fn.readfile, path)
    if ok and lines then
      local current_h = nil
      for lnum, line in ipairs(lines) do
        local keyword, title = line:match("^%*%*%s+(%S+)%s+(.+)$")
        if keyword and open_keyword(keyword) then
          if current_h then
            table.insert(items, { headline = current_h, path = path })
          end
          local tags = { "youtube" }
          local tag_group = title:match("%s:([%w_@#%%:]+):%s*$")
          for tag in (tag_group or ""):gmatch("[^:]+") do
            table.insert(tags, tag)
          end
          current_h = {
            title = vim.trim((title:gsub("%s+:[%w_@#%%:]+:%s*$", ""))),
            todo_value = keyword,
            todo_type = "TODO",
            position = { start_line = lnum },
            tags = tags,
            props = {},
            get_property = function(self, k)
              return self.props[k] or self.props[k:lower()]
            end,
          }
        elseif current_h then
          local k, v = line:match("^:([%w_-]+):%s*(.-)%s*$")
          if k then
            current_h.props[k] = v
            current_h.props[k:lower()] = v
          elseif line:match("^%*") then
            table.insert(items, { headline = current_h, path = path })
            current_h = nil
          end
        end
      end
      if current_h then
        table.insert(items, { headline = current_h, path = path })
      end
    end
  end

  _cached_youtube_items = items
  _cache_time = now
  return items
end

M.collect = get_all_youtube_items

local function open_youtube_query(opts)
  local query_string = opts.args or ""
  local all_items = get_all_youtube_items()
  local items = {}

  for _, item in ipairs(all_items) do
    if matches_query(item.headline, query_string) then
      table.insert(items, item)
    end
  end

  -- Sort (Unwrap to access properties)
  table.sort(items, function(a, b)
    local t_a = parse_date(a.headline:get_property("Published"))
    local t_b = parse_date(b.headline:get_property("Published"))
    return t_a < t_b
  end)

  -- Build Quickfix List
  local qf = {}
  for _, item in ipairs(items) do
    local h = item.headline

    -- Use the explicit path we captured (Expand ~ just in case)
    local abs_path = vim.fn.fnamemodify(vim.fn.expand(item.path), ":p")

    local title = h.title or "No Title"
    local pub = h:get_property("Published") or ""

    local debug_info = ""
    if query_string ~= "" then
      if query_string:match("Duration") then
        local dur = h:get_property("Duration")
        if dur then
          debug_info = debug_info .. string.format(" [Dur: %s]", dur)
        end
      end
      if query_string:match("Importance") then
        local imp = h:get_property("Importance")
        if imp then
          debug_info = debug_info .. string.format(" [Imp: %s]", imp)
        end
      end
    end

    table.insert(qf, {
      filename = abs_path,
      lnum = h.position.start_line,
      text = string.format("[%s] %s (%s)%s", h.todo_value, title, pub, debug_info),
    })
  end

  if #qf == 0 then
    print("No videos found matching: " .. (query_string == "" and "All" or query_string))
  else
    vim.fn.setqflist(qf, "r")
    vim.cmd("copen")
    print(string.format("Found %d videos.", #qf))
  end
end

local function open_random_video(opts)
  local query_string = opts.args or ""
  local all_items = get_all_youtube_items()
  local matching = {}

  for _, item in ipairs(all_items) do
    if matches_query(item.headline, query_string) then
      table.insert(matching, item)
    end
  end

  if #matching == 0 then
    print("No YouTube videos found matching: " .. (query_string == "" and "All" or query_string))
    return
  end

  math.randomseed(os.time())
  local selection = {}
  local count = math.min(3, #matching)
  for _ = 1, count do
    local idx = math.random(#matching)
    table.insert(selection, table.remove(matching, idx))
  end

  local qf = {}
  for _, item in ipairs(selection) do
    local h = item.headline
    local abs_path = vim.fn.fnamemodify(vim.fn.expand(item.path), ":p")
    table.insert(qf, {
      filename = abs_path,
      lnum = h.position.start_line,
      text = string.format("[%s] %s", h.todo_value, h.title),
    })
  end

  vim.fn.setqflist(qf, "r")
  vim.cmd("copen")
  print(string.format("Selected %d random videos matching: %s", #qf, query_string == "" and "All" or query_string))
end

local function open_random_video_by_date(opts, mode)
  local query_string = opts.args or ""
  local all_items = get_all_youtube_items()
  local candidates = {}

  for _, item in ipairs(all_items) do
    if matches_query(item.headline, query_string) then
      local pub_str = item.headline:get_property("Published")
      local pub_time = parse_date(pub_str)
      table.insert(candidates, {
        headline = item.headline,
        path = item.path,
        published = pub_time,
        pub_str = pub_str or "",
      })
    end
  end

  if #candidates == 0 then
    print("No YouTube videos found matching: " .. (query_string == "" and "All" or query_string))
    return
  end

  local function format_days(days)
    if not days then
      return "all-time"
    end
    if days >= 365 and days % 365 == 0 then
      local yrs = math.floor(days / 365)
      return string.format("%d year%s", yrs, yrs > 1 and "s" or "")
    elseif days % 30 == 0 then
      local mos = math.floor(days / 30)
      return string.format("%d month%s", mos, mos > 1 and "s" or "")
    else
      return string.format("%d days", days)
    end
  end

  local WINDOW_STEPS = { 30, 60, 90, 180, 365, 730, 1095, 1460, 1825, 2555, 3650, 5475, 7300, nil }
  local target_count = math.min(3, #candidates)
  local selected_pool = {}
  local matched_step_days = nil
  local expanded_from_first = false

  if mode == "recent" then
    local now = os.time()
    for idx, days in ipairs(WINDOW_STEPS) do
      local pool = {}
      if days ~= nil then
        local cutoff = now - (days * 86400)
        for _, item in ipairs(candidates) do
          if item.published > 0 and item.published >= cutoff then
            table.insert(pool, item)
          end
        end
      else
        pool = candidates
      end

      if #pool >= target_count then
        selected_pool = pool
        matched_step_days = days
        if idx > 1 then
          expanded_from_first = true
        end
        break
      end
    end
  elseif mode == "oldest" then
    local min_time = nil
    for _, item in ipairs(candidates) do
      if item.published > 0 then
        if not min_time or item.published < min_time then
          min_time = item.published
        end
      end
    end

    if not min_time then
      selected_pool = candidates
      matched_step_days = nil
    else
      for idx, days in ipairs(WINDOW_STEPS) do
        local pool = {}
        if days ~= nil then
          local cutoff = min_time + (days * 86400)
          for _, item in ipairs(candidates) do
            if item.published > 0 and item.published <= cutoff then
              table.insert(pool, item)
            end
          end
        else
          pool = candidates
        end

        if #pool >= target_count then
          selected_pool = pool
          matched_step_days = days
          if idx > 1 then
            expanded_from_first = true
          end
          break
        end
      end
    end
  else
    selected_pool = candidates
  end

  if #selected_pool == 0 then
    selected_pool = candidates
  end

  math.randomseed(os.time())
  local selection = {}
  local pool_copy = {}
  for _, item in ipairs(selected_pool) do
    table.insert(pool_copy, item)
  end

  local count = math.min(3, #pool_copy)
  for _ = 1, count do
    local rand_idx = math.random(#pool_copy)
    table.insert(selection, table.remove(pool_copy, rand_idx))
  end

  local qf = {}
  for _, item in ipairs(selection) do
    local h = item.headline
    local abs_path = vim.fn.fnamemodify(vim.fn.expand(item.path), ":p")
    local pub_suffix = item.pub_str ~= "" and (" (" .. item.pub_str .. ")") or ""
    table.insert(qf, {
      filename = abs_path,
      lnum = h.position.start_line,
      text = string.format("[%s] %s%s", h.todo_value, h.title, pub_suffix),
    })
  end

  vim.fn.setqflist(qf, "r")
  vim.cmd("copen")

  local window_desc
  if matched_step_days then
    local prefix = (mode == "oldest") and "earliest" or "past"
    local expanded_str = expanded_from_first and " (expanded)" or ""
    window_desc = string.format("%s %s%s", prefix, format_days(matched_step_days), expanded_str)
  else
    window_desc = "all-time"
  end

  local query_desc = query_string == "" and "All" or query_string
  print(string.format("Selected %d random %s videos [%s] matching: %s", #qf, mode, window_desc, query_desc))
end


function M.setup_commands()
  vim.api.nvim_create_user_command("OrgYoutube", open_youtube_query, { nargs = "?" })
  vim.api.nvim_create_user_command("OrgYoutubeRandom", open_random_video, { nargs = "?" })
  vim.api.nvim_create_user_command("OrgYoutubeRandomRecent", function(opts)
    open_random_video_by_date(opts, "recent")
  end, { nargs = "?" })
  vim.api.nvim_create_user_command("OrgYoutubeRandomOldest", function(opts)
    open_random_video_by_date(opts, "oldest")
  end, { nargs = "?" })
  vim.api.nvim_create_user_command("OrgYoutubeReload", function()
    get_all_youtube_items(true)
    print("Reloaded YouTube items cache.")
  end, {})
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("org_youtube_cache", { clear = true }),
    pattern = "*.org",
    callback = function(args)
      if core.within(args.match, youtube_dir()) then
        _cached_youtube_items = nil
      end
    end,
  })
end

function M.setup_buffer_keymaps()
  vim.keymap.set("n", "<leader>oyt", ":OrgYoutube<CR>", { buffer = 0, desc = "YouTube All" })
  vim.keymap.set("n", "<leader>oys", ":OrgYoutube Duration<600<CR>", { buffer = 0, desc = "YouTube Short" })
  vim.keymap.set("n", "<leader>oyi", ":OrgYoutube Importance=5<CR>", { buffer = 0, desc = "YouTube Important" })
  vim.keymap.set("n", "<leader>oyr", ":OrgYoutubeRandom<CR>", { buffer = 0, desc = "YouTube Random" })
  vim.keymap.set("n", "<leader>oyR", ":OrgYoutubeRandom Duration<600", { buffer = 0, desc = "YouTube Random Query" })
  vim.keymap.set("n", "<leader>oyn", ":OrgYoutubeRandomRecent<CR>", { buffer = 0, desc = "YouTube Random Recent" })
  vim.keymap.set("n", "<leader>oyN", ":OrgYoutubeRandomRecent Duration<600", { buffer = 0, desc = "YouTube Random Recent Short" })
  vim.keymap.set("n", "<leader>oyo", ":OrgYoutubeRandomOldest<CR>", { buffer = 0, desc = "YouTube Random Oldest" })
  vim.keymap.set("n", "<leader>oyO", ":OrgYoutubeRandomOldest Duration<600", { buffer = 0, desc = "YouTube Random Oldest Short" })
end

function M.setup()
  M.setup_commands()
end

return M
