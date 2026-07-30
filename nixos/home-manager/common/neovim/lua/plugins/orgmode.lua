require("org-bullets").setup()
--require('headlines').setup()

local orgmode = require("orgmode")
local params = {
  -- org_agenda_files = { '~/org/life/**/*.org', ('%s/**/*.org'):format(vim.fn.getcwd()) },
  org_agenda_files = { ("%s/**/*.org"):format(vim.fn.getcwd()) },
  org_default_notes_file = "~/org/life/refile.org",
  org_tags_column = 0,
  org_hide_emphasis_markers = true,
  -- org_agenda_use_virtual_text = false,
  org_todo_keywords = { "TODO(t)", "DOING(p)", "HOLD(h)", "IDEA(i)", "NOTE(n)", "|", "DONE(d)", "SKIP(s)" },
  org_todo_keyword_faces = {
    DOING = ":foreground orange :slant italic :underline on :weight bold",
    HOLD = ":foreground grey :weight bold",
    SKIP = ":foreground purple :weight bold",
    IDEA = ":foreground green :slant italic",
    NOTE = ":foreground yellow :weight bold",
  },
  org_capture_templates = {
    t = { description = "Task", template = "* TODO %?\n  %u" },
    i = { description = "Idea", template = "* IDEA %?\n  %u" },
    n = { description = "Note", template = "* NOTE %?\n  %u" },
    j = { description = "Journal", template = "** %u day journal\n %?", target = "~/org/life/journal/journal.org" },
  },
  org_agenda_custom_commands = {
    i = {
      description = "Tasks and ideas review",
      types = {
        {
          type = "tags_todo",
          org_agenda_todo_ignore_scheduled = "all",
          org_agenda_overriding_header = "All todos",
          match = "-recurring-idea-work-youtube-article/TODO",
        },
        {
          type = "tags_todo",
          org_agenda_todo_ignore_scheduled = "all",
          org_agenda_overriding_header = "All ideas",
          match = '+TODO="IDEA"',
        },
      },
    },
    y = {
      description = "Youtube",
      types = {
        {
          type = "tags_todo",
          org_agenda_todo_ignore_scheduled = "all",
          org_agenda_overriding_header = "All videos",
          match = "+youtube+Duration<300",
          org_agenda_sorting_strategy = { "category-down" },
        },
      },
    },
  },
}

orgmode.setup(params)

-- ── Calorie Tracker ──────────────────────────────────────────────
-- Food library is read from the table under "* Food Library" in ~/org/life/calories.org.
-- Add/edit rows there — no rebuild needed.

local function load_food_library()
  local path = vim.fn.expand("~/org/life/calories.org")
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines or #lines == 0 then
    return {}
  end

  local in_section, in_data = false, false
  local foods = {}

  for _, line in ipairs(lines) do
    if line:find("^%* Food Library") then
      in_section = true
    elseif in_section and line:find("^%* ") then
      break
    elseif in_section and line:find("^|") then
      if line:find("^|%-") then
        in_data = not in_data
      elseif in_data then
        local cells = vim.split(line, "|", { plain = true })
        table.remove(cells, 1)
        table.remove(cells)
        for i, c in ipairs(cells) do
          cells[i] = vim.trim(c)
        end
        if #cells >= 5 and cells[1] ~= "" then
          local cal = tonumber(((cells[2] or ""):gsub(",", "."))) or 0
          local pro = tonumber(((cells[3] or ""):gsub(",", "."))) or 0
          local carb = tonumber(((cells[4] or ""):gsub(",", "."))) or 0
          local fat = tonumber(((cells[5] or ""):gsub(",", "."))) or 0
          table.insert(foods, { name = cells[1], cal = cal, pro = pro, carb = carb, fat = fat })
        end
      end
    end
  end

  table.insert(foods, { name = "--- Custom Entry ---", cal = 0, pro = 0, carb = 0, fat = 0, custom = true })
  return foods
end

local table_header = "| Meal | Food | G | Cal | Pro | Carb | Fat |"
local table_sep = "|------+------+---+-----+-----+------+-----|"

local function is_table_separator(line)
  return line:match("^|%-") ~= nil
end

local function get_current_day_heading_range()
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1]

  local heading_start = nil
  for i = cursor_line, 1, -1 do
    if lines[i]:match("^%* %d%d%d%d%-%d%d%-%d%d") then
      heading_start = i
      break
    end
  end

  if not heading_start then
    local today = os.date("%Y-%m-%d")
    for i, line in ipairs(lines) do
      if line:find("* " .. today, 1, true) then
        heading_start = i
        break
      end
    end
  end

  return heading_start, bufnr, lines
end

local function find_total_line(lines, heading_start)
  for i = heading_start, #lines do
    if lines[i]:match("^|%s*TOTAL%s*|") then
      return i
    end
    if i > heading_start and lines[i]:find("* ", 1, true) then
      break
    end
  end
  return nil
end

local function find_data_rows(lines, heading_start)
  local rows = {}
  local in_data = false
  for i = heading_start, #lines do
    local line = lines[i]
    if line:find("* ", 1, true) and i > heading_start then
      break
    end
    if is_table_separator(line) then
      if in_data then
        return rows
      else
        in_data = true
      end
    elseif in_data and line:match("^|") then
      table.insert(rows, { lnum = i, line = line })
    end
  end
  return rows
end

local function parse_row_cells(line)
  local cells = vim.split(line, "|", { plain = true })
  table.remove(cells, 1)
  table.remove(cells)
  for i, cell in ipairs(cells) do
    cells[i] = vim.trim(cell)
  end
  return cells
end

local function row_tonumber(s)
  return tonumber((tostring(s):gsub(",", "."):match("[%d.]+"))) or 0
end

_G.create_calorie_day = function()
  local date = os.date("%Y-%m-%d %A")
  local lines = {
    "",
    "* " .. date,
    table_header,
    table_sep,
    "| Breakfast |      |   |     |     |      |     |",
    "| Lunch     |      |   |     |     |      |     |",
    "| Dinner    |      |   |     |     |      |     |",
    "| Snack     |      |   |     |     |      |     |",
    table_sep,
    "| TOTAL     |      |   |   0 |   0 |    0 |   0 |",
    "",
  }
  vim.api.nvim_put(lines, "l", true, true)
end

_G.add_food_row = function()
  local heading_start, bufnr = get_current_day_heading_range()
  if not heading_start then
    print("[calories] Today's entry not found. Use <leader>od to create it first.")
    return
  end

  local common_foods = load_food_library()

  local food_names = {}
  for _, f in ipairs(common_foods) do
    table.insert(food_names, f.name)
  end

  vim.ui.select(food_names, {
    prompt = "Select food:",
    format_item = function(item)
      for _, f in ipairs(common_foods) do
        if f.name == item then
          if f.custom then
            return item
          end
          return string.format("%-30s  %3dc | %3dp | %3dcb | %3df  /100g", item, f.cal, f.pro, f.carb, f.fat)
        end
      end
      return item
    end,
  }, function(choice)
    if not choice then
      return
    end

    local food
    for _, f in ipairs(common_foods) do
      if f.name == choice then
        food = f
        break
      end
    end
    if not food then
      return
    end

    if food.custom then
      vim.ui.input({ prompt = "Food name: " }, function(name)
        if not name or name == "" then
          return
        end
        vim.ui.input({ prompt = "Calories (per 100g): " }, function(cal_str)
          local cal = tonumber(((cal_str or ""):gsub(",", "."))) or 0
          vim.ui.input({ prompt = "Protein (g per 100g): " }, function(pro_str)
            local pro = tonumber(((pro_str or ""):gsub(",", "."))) or 0
            vim.ui.input({ prompt = "Carbs (g per 100g): " }, function(carb_str)
              local carb = tonumber(((carb_str or ""):gsub(",", "."))) or 0
              vim.ui.input({ prompt = "Fat (g per 100g): " }, function(fat_str)
                local fat = tonumber(((fat_str or ""):gsub(",", "."))) or 0
                vim.ui.input({ prompt = "Grams: ", default = "100" }, function(grams_str)
                  local grams = tonumber(((grams_str or ""):gsub(",", ".")))
                  if not grams or grams <= 0 then
                    return
                  end
                  local factor = grams / 100
                  _do_insert_food_row(
                    bufnr,
                    "",
                    name,
                    grams,
                    math.floor(cal * factor + 0.5),
                    math.floor(pro * factor + 0.5),
                    math.floor(carb * factor + 0.5),
                    math.floor(fat * factor + 0.5)
                  )
                end)
              end)
            end)
          end)
        end)
      end)
    else
      vim.ui.input({ prompt = "Grams: ", default = "100" }, function(grams_str)
        local grams = tonumber(((grams_str or ""):gsub(",", ".")))
        if not grams or grams <= 0 then
          return
        end
        local factor = grams / 100
        local cal = math.floor(food.cal * factor + 0.5)
        local pro = math.floor(food.pro * factor + 0.5)
        local carb = math.floor(food.carb * factor + 0.5)
        local fat = math.floor(food.fat * factor + 0.5)
        _do_insert_food_row(bufnr, "", food.name, grams, cal, pro, carb, fat)
      end)
    end
  end)
end

_G.recalc_current_row = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
  if not line or not line:match("^|") then
    print("[calories] Not on a table row.")
    return
  end

  local cells = parse_row_cells(line)
  table.remove(cells, 1)
  if #cells < 6 then
    print("[calories] Not enough columns in this row.")
    return
  end

  local name = cells[1] or ""
  if name == "" then
    print("[calories] No food name on this row.")
    return
  end

  local cur_g = tonumber(((cells[2] or ""):gsub(",", "."))) or 0
  local cur_cal = tonumber(((cells[3] or ""):gsub(",", "."))) or 0
  local cur_pro = tonumber(((cells[4] or ""):gsub(",", "."))) or 0
  local cur_carb = tonumber(((cells[5] or ""):gsub(",", "."))) or 0
  local cur_fat = tonumber(((cells[6] or ""):gsub(",", "."))) or 0

  local per_cal, per_pro, per_carb, per_fat
  local found = false
  local common_foods = load_food_library()
  for _, f in ipairs(common_foods) do
    if f.name == name and not f.custom then
      per_cal, per_pro, per_carb, per_fat = f.cal, f.pro, f.carb, f.fat
      found = true
      break
    end
  end

  if not found and cur_g > 0 then
    per_cal = (cur_cal * 100) / cur_g
    per_pro = (cur_pro * 100) / cur_g
    per_carb = (cur_carb * 100) / cur_g
    per_fat = (cur_fat * 100) / cur_g
  elseif not found then
    per_cal, per_pro, per_carb, per_fat = cur_cal, cur_pro, cur_carb, cur_fat
  end

  vim.ui.input({
    prompt = string.format(
      "Grams (%s, per100g: %dC/%dP/%dCb/%dF): ",
      name,
      math.floor(per_cal + 0.5),
      math.floor(per_pro + 0.5),
      math.floor(per_carb + 0.5),
      math.floor(per_fat + 0.5)
    ),
    default = tostring(cur_g),
  }, function(grams_str)
    local grams = tonumber(((grams_str or ""):gsub(",", ".")))
    if not grams or grams <= 0 then
      return
    end
    local factor = grams / 100
    local cal = math.floor(per_cal * factor + 0.5)
    local pro = math.floor(per_pro * factor + 0.5)
    local carb = math.floor(per_carb * factor + 0.5)
    local fat = math.floor(per_fat * factor + 0.5)

    local g_str = grams > 0 and tostring(grams) or ""
    local row_str =
        string.format("| %-9s | %-20s | %s | %3d | %3d | %4d | %3d |", "", name, g_str, cal, pro, carb, fat)

    vim.api.nvim_buf_set_lines(bufnr, cursor[1] - 1, cursor[1], false, { row_str })
    _G.calc_daily_totals()
  end)
end

_G.goto_today = function()
  local today = os.date("%Y-%m-%d")
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:find("* " .. today, 1, true) then
      vim.api.nvim_win_set_cursor(0, { i + 1, 0 })
      vim.cmd("normal zv")
      return
    end
  end
  print("[calories] No entry found for today. Use <leader>od to create one.")
end

function _do_insert_food_row(bufnr, meal, food_name, grams, cal, pro, carb, fat)
  cal = math.floor(cal + 0.5)
  pro = math.floor(pro + 0.5)
  carb = math.floor(carb + 0.5)
  fat = math.floor(fat + 0.5)
  local heading_start, _, lines = get_current_day_heading_range()
  if not heading_start or not lines then
    print("[calories] Could not read buffer.")
    return
  end

  local sep_before_total = nil
  local sep_count = 0
  for i = heading_start, #lines do
    if lines[i]:find("* ", 1, true) and i > heading_start then
      break
    end
    if is_table_separator(lines[i]) then
      sep_count = sep_count + 1
      if sep_count == 2 then
        sep_before_total = i
        break
      end
    end
  end

  if not sep_before_total then
    print("[calories] Could not find table separator before TOTAL.")
    return
  end

  local grams_str = grams > 0 and tostring(grams) or ""
  local row_str =
      string.format("| %-9s | %-20s | %s | %3d | %3d | %4d | %3d |", meal, food_name, grams_str, cal, pro, carb, fat)

  vim.api.nvim_buf_set_lines(bufnr, sep_before_total - 1, sep_before_total - 1, false, { row_str })

  _G.calc_daily_totals()
end

_G.calc_daily_totals = function()
  local heading_start, bufnr, lines = get_current_day_heading_range()
  if not heading_start then
    vim.notify("[calories] Today's entry not found.", vim.log.levels.WARN)
    return
  end

  local data_rows = find_data_rows(lines, heading_start)
  local total_ln = find_total_line(lines, heading_start)
  if not total_ln then
    vim.notify("[calories] Could not find TOTAL row.", vim.log.levels.WARN)
    return
  end

  vim.notify(
    string.format(
      "[calories] heading at line %d, %d data rows, TOTAL at line %d",
      heading_start,
      #data_rows,
      total_ln
    ),
    vim.log.levels.INFO
  )

  local sums = { cal = 0, pro = 0, carb = 0, fat = 0 }
  local count = 0

  for _, row in ipairs(data_rows) do
    local cells = parse_row_cells(row.line)
    table.remove(cells, 1)
    local name = cells[1] or ""
    if name ~= "" and not name:match("^TOTAL$") and #cells >= 6 then
      local cal = row_tonumber(cells[3])
      local pro = row_tonumber(cells[4])
      local carb = row_tonumber(cells[5])
      local fat = row_tonumber(cells[6])
      sums.cal = sums.cal + cal
      sums.pro = sums.pro + pro
      sums.carb = sums.carb + carb
      sums.fat = sums.fat + fat
      count = count + 1
    end
  end

  local total_row = string.format(
    "| TOTAL     | %-20s |   | %3d | %3d | %4d | %3d |",
    tostring(count) .. " items",
    math.floor(sums.cal + 0.5),
    math.floor(sums.pro + 0.5),
    math.floor(sums.carb + 0.5),
    math.floor(sums.fat + 0.5)
  )

  vim.api.nvim_buf_set_lines(bufnr, total_ln - 1, total_ln, false, { total_row })
  vim.notify(
    string.format(
      "[calories] %d items: %d Cal | P:%dg C:%dg F:%dg",
      count,
      math.floor(sums.cal + 0.5),
      math.floor(sums.pro + 0.5),
      math.floor(sums.carb + 0.5),
      math.floor(sums.fat + 0.5)
    ),
    vim.log.levels.INFO
  )
end

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

-- Helper: Inherited Tags
local function has_youtube_tag(headline)
  local current = headline
  while current do
    for _, tag in ipairs(current.tags or {}) do
      if tag == "youtube" then
        return true
      end
    end
    current = current.parent
  end
  return false
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

local function open_youtube_query(opts)
  local query_string = opts.args or ""
  local org_api = require("orgmode.api")

  -- Load and Collect (Store Path Explicitly)
  local files = org_api.load()
  local items = {}

  for _, file in ipairs(files) do
    -- Capture the filename string from the file object directly
    local file_path = file.filename

    for _, h in ipairs(file.headlines) do
      if h.todo_type == "TODO" and has_youtube_tag(h) then
        if matches_query(h, query_string) then
          -- Store both the headline AND the path in a wrapper object
          table.insert(items, { headline = h, path = file_path })
        end
      end
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
  local org_api = require("orgmode.api")

  local files = org_api.load()
  local all_items = {}
  for _, file in ipairs(files) do
    local file_path = file.filename
    for _, h in ipairs(file.headlines) do
      if h.todo_type == "TODO" and has_youtube_tag(h) then
        if matches_query(h, query_string) then
          table.insert(all_items, { headline = h, path = file_path })
        end
      end
    end
  end

  if #all_items == 0 then
    print("No YouTube videos found matching: " .. (query_string == "" and "All" or query_string))
    return
  end

  math.randomseed(os.time())
  local selection = {}
  local count = math.min(3, #all_items)
  for _ = 1, count do
    local idx = math.random(#all_items)
    table.insert(selection, table.remove(all_items, idx))
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

vim.api.nvim_create_user_command("OrgYoutube", open_youtube_query, { nargs = "?" })
vim.api.nvim_create_user_command("OrgYoutubeRandom", open_random_video, { nargs = "?" })

vim.api.nvim_create_autocmd("FileType", {
  pattern = "org",
  group = vim.api.nvim_create_augroup("orgmode_calorie_tracker", { clear = true }),
  callback = function()
    pcall(vim.cmd, "TableModeEnable")
    vim.keymap.set(
      "n",
      "<leader>od",
      "<cmd>lua _G.create_calorie_day()<CR>",
      { buffer = 0, desc = "New calorie day" }
    )
    vim.keymap.set("n", "<leader>of", "<cmd>lua _G.add_food_row()<CR>", { buffer = 0, desc = "Add food" })
    vim.keymap.set("n", "<leader>ol", "<cmd>lua _G.calc_daily_totals()<CR>", { buffer = 0, desc = "Calc totals" })
    vim.keymap.set("n", "<leader>or", "<cmd>lua _G.recalc_current_row()<CR>", { buffer = 0, desc = "Recalc row" })
    vim.keymap.set("n", "<leader>on", "<cmd>lua _G.goto_today()<CR>", { buffer = 0, desc = "Go to today" })
    vim.keymap.set("n", "<leader>op", require("telescope").extensions.orgmode.refile_heading)
    vim.keymap.set("n", "<leader>os", require("telescope").extensions.orgmode.search_headings)
    vim.keymap.set("n", "<leader>oyt", ":OrgYoutube<CR>", { desc = "YouTube All" })
    vim.keymap.set("n", "<leader>oys", ":OrgYoutube Duration<600<CR>", { desc = "YouTube Short" })
    vim.keymap.set("n", "<leader>oyi", ":OrgYoutube Importance=5<CR>", { desc = "YouTube Important" })
    vim.keymap.set("n", "<leader>oyr", ":OrgYoutubeRandom<CR>", { desc = "YouTube Random" })
    vim.keymap.set("n", "<leader>oyR", ":OrgYoutubeRandom Duration<600", { desc = "YouTube Random Query" })
  end,
})
