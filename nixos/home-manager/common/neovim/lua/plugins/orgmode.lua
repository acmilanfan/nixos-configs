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

local function fmt_num(n)
  n = tonumber(n) or 0
  if n == math.floor(n) then
    return string.format("%d", n)
  else
    return string.format("%.1f", n):gsub("%.0$", "")
  end
end

local function eval_grams(input_str)
  if not input_str then
    return nil
  end
  local clean = (input_str:gsub(",", "."):match("[%d%+%-%*%/%.%(%)%s]+"))
  if not clean or clean:match("^%s*$") then
    return nil
  end
  local fn = load("return " .. clean)
  if fn then
    local ok, res = pcall(fn)
    if ok and type(res) == "number" and res > 0 then
      return math.floor(res * 10 + 0.5) / 10
    end
  end
  return tonumber((input_str:gsub(",", "."):match("[%d.]+")))
end

local function append_to_food_library(name, cal, pro, carb, fat)
  local path = vim.fn.expand("~/org/life/calories.org")
  local bufnr = vim.fn.bufnr(path)
  local is_buf = (bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr))
  local lines = is_buf and vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) or vim.fn.readfile(path)

  if not lines or #lines == 0 then
    vim.notify("[calories] Could not read calories.org", vim.log.levels.ERROR)
    return false
  end

  local in_section = false
  local last_table_line = nil
  for i, line in ipairs(lines) do
    if line:find("^%* Food Library") then
      in_section = true
    elseif in_section and line:find("^%* ") then
      break
    elseif in_section and line:match("^|") then
      local cells = vim.split(line, "|", { plain = true })
      if #cells >= 3 then
        local existing_name = vim.trim(cells[2] or "")
        if existing_name:lower() == name:lower() then
          vim.notify(string.format("[calories] '%s' is already in Food Library.", name), vim.log.levels.INFO)
          return false
        end
      end
      last_table_line = i
    end
  end

  if not last_table_line then
    vim.notify("[calories] Could not find Food Library table in calories.org", vim.log.levels.WARN)
    return false
  end

  local new_row = string.format(
    "| %-34s | %-3s | %-4s | %-4s | %-4s |",
    name,
    fmt_num(cal),
    fmt_num(pro),
    fmt_num(carb),
    fmt_num(fat)
  )

  if is_buf then
    vim.api.nvim_buf_set_lines(bufnr, last_table_line, last_table_line, false, { new_row })
  else
    table.insert(lines, last_table_line + 1, new_row)
    vim.fn.writefile(lines, path)
  end

  vim.notify(
    string.format(
      "[calories] Added '%s' to Food Library (%sc/%sp/%scb/%sf)",
      name,
      fmt_num(cal),
      fmt_num(pro),
      fmt_num(carb),
      fmt_num(fat)
    ),
    vim.log.levels.INFO
  )
  return true
end

local function parse_food_input(input)
  if not input or input:match("^%s*$") then
    return nil
  end

  -- Case 1: Tagged format: "Protein Bar 220c 20p 15cb 8f 60g"
  local c_cal = input:match("(%d+%.?%d*)%s*c[al]*%f[%A]")
  local c_pro = input:match("(%d+%.?%d*)%s*p%f[%A]")
  local c_carb = input:match("(%d+%.?%d*)%s*cb%f[%A]") or input:match("(%d+%.?%d*)%s*carb[s]?%f[%A]")
  local c_fat = input:match("(%d+%.?%d*)%s*f[at]*%f[%A]")
  local c_g = input:match("(%d+%.?%d*)%s*g%f[%A]")

  if c_cal and c_pro then
    local name = input
    name = name:gsub("(%d+%.?%d*)%s*c[al]*%f[%A]", "")
    name = name:gsub("(%d+%.?%d*)%s*cb%f[%A]", "")
    name = name:gsub("(%d+%.?%d*)%s*carb[s]?%f[%A]", "")
    name = name:gsub("(%d+%.?%d*)%s*p%f[%A]", "")
    name = name:gsub("(%d+%.?%d*)%s*f[at]*%f[%A]", "")
    name = name:gsub("(%d+%.?%d*)%s*g%f[%A]", "")
    name = vim.trim(name:gsub("[,:]", " "))
    local cal = tonumber(c_cal) or 0
    local pro = tonumber(c_pro) or 0
    local carb = tonumber(c_carb) or 0
    local fat = tonumber(c_fat) or 0
    local g = tonumber(c_g)
    return { name = name, cal = cal, pro = pro, carb = carb, fat = fat, grams = g, is_serving = (g ~= nil and g ~= 100) }
  end

  -- Case 2: Portion syntax: "Protein Bar @ 60g: 220, 20, 15, 8"
  local name_part, portion_g, rest = input:match("^(.-)%s*[@/]%s*(%d+%.?%d*)%s*g?%s*[:,-]%s*(.+)$")
  if name_part and portion_g and rest then
    local parts = vim.split(rest, "[,%s]+", { trimempty = true })
    if #parts >= 4 then
      local cal = tonumber((parts[1]:gsub(",", "."))) or 0
      local pro = tonumber((parts[2]:gsub(",", "."))) or 0
      local carb = tonumber((parts[3]:gsub(",", "."))) or 0
      local fat = tonumber((parts[4]:gsub(",", "."))) or 0
      local g = tonumber((portion_g:gsub(",", "."))) or 100
      return { name = vim.trim(name_part), cal = cal, pro = pro, carb = carb, fat = fat, grams = g, is_serving = true }
    end
  end

  -- Case 3: Comma separated: "Name, cal, pro, carb, fat [, grams]"
  if input:find(",") then
    local parts = vim.split(input, ",", { trimempty = true })
    if #parts >= 5 then
      local name = vim.trim(parts[1])
      local cal = tonumber((vim.trim(parts[2]):gsub(",", "."))) or 0
      local pro = tonumber((vim.trim(parts[3]):gsub(",", "."))) or 0
      local carb = tonumber((vim.trim(parts[4]):gsub(",", "."))) or 0
      local fat = tonumber((vim.trim(parts[5]):gsub(",", "."))) or 0
      local g = parts[6] and tonumber((vim.trim(parts[6]):gsub("[^%d%.]", ""))) or nil
      return { name = name, cal = cal, pro = pro, carb = carb, fat = fat, grams = g }
    end
  end

  -- Case 4: Space separated: "Name with spaces 220 20 15 8 [60]"
  local parts = vim.split(input, "%s+", { trimempty = true })
  local num_start = nil
  for i = #parts, 1, -1 do
    local n = tonumber((parts[i]:gsub(",", ".")))
    if n then
      num_start = i
    else
      break
    end
  end
  if num_start and (#parts - num_start + 1) >= 4 then
    local nums = {}
    for i = num_start, #parts do
      table.insert(nums, tonumber((parts[i]:gsub(",", "."))))
    end
    local name = table.concat({ unpack(parts, 1, num_start - 1) }, " ")
    return {
      name = name,
      cal = nums[1] or 0,
      pro = nums[2] or 0,
      carb = nums[3] or 0,
      fat = nums[4] or 0,
      grams = nums[5],
    }
  end

  return nil
end

local function load_food_library()
  local path = vim.fn.expand("~/org/life/calories.org")
  local bufnr = vim.fn.bufnr(path)
  local lines
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  else
    local ok, res = pcall(vim.fn.readfile, path)
    if ok and res then
      lines = res
    end
  end
  if not lines or #lines == 0 then
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

  table.insert(foods, { name = "--- Custom Entry (Quick Add) ---", cal = 0, pro = 0, carb = 0, fat = 0, custom = true })
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

local function _do_insert_food_row(bufnr, meal, food_name, grams, cal, pro, carb, fat)
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

  local grams_str = grams and grams > 0 and fmt_num(grams) or ""
  local row_str =
      string.format("| %-9s | %-22s | %-4s | %4d | %3d | %4d | %3d |", meal or "", food_name, grams_str, cal, pro, carb, fat)

  vim.api.nvim_buf_set_lines(bufnr, sep_before_total - 1, sep_before_total - 1, false, { row_str })

  _G.calc_daily_totals()
end

_G.quick_add_food = function(initial_input)
  local heading_start, bufnr = get_current_day_heading_range()
  if not heading_start then
    vim.notify("[calories] Today's entry not found. Use <leader>od to create it first.", vim.log.levels.WARN)
    return
  end

  local function process_input(input_str)
    if not input_str or input_str:match("^%s*$") then
      return
    end
    local parsed = parse_food_input(input_str)
    if not parsed or parsed.name == "" then
      vim.notify(
        "[calories] Could not parse. Examples:\n  'Skyr Vanilla, 71, 8.6, 8.3, 0.2, 150'\n  'Bar @ 60g: 220, 20, 15, 8'",
        vim.log.levels.WARN
      )
      return
    end

    local per_cal, per_pro, per_carb, per_fat
    local eaten_g, eaten_cal, eaten_pro, eaten_carb, eaten_fat

    if parsed.is_serving and parsed.grams and parsed.grams > 0 then
      local factor = 100 / parsed.grams
      per_cal = math.floor(parsed.cal * factor + 0.5)
      per_pro = math.floor(parsed.pro * factor * 10 + 0.5) / 10
      per_carb = math.floor(parsed.carb * factor * 10 + 0.5) / 10
      per_fat = math.floor(parsed.fat * factor * 10 + 0.5) / 10
      eaten_g = parsed.grams
      eaten_cal = parsed.cal
      eaten_pro = parsed.pro
      eaten_carb = parsed.carb
      eaten_fat = parsed.fat

      append_to_food_library(parsed.name, per_cal, per_pro, per_carb, per_fat)
      _do_insert_food_row(bufnr, "", parsed.name, eaten_g, eaten_cal, eaten_pro, eaten_carb, eaten_fat)
    else
      per_cal = parsed.cal
      per_pro = parsed.pro
      per_carb = parsed.carb
      per_fat = parsed.fat
      append_to_food_library(parsed.name, per_cal, per_pro, per_carb, per_fat)

      if parsed.grams and parsed.grams > 0 then
        eaten_g = parsed.grams
        local factor = eaten_g / 100
        eaten_cal = math.floor(per_cal * factor + 0.5)
        eaten_pro = math.floor(per_pro * factor + 0.5)
        eaten_carb = math.floor(per_carb * factor + 0.5)
        eaten_fat = math.floor(per_fat * factor + 0.5)
        _do_insert_food_row(bufnr, "", parsed.name, eaten_g, eaten_cal, eaten_pro, eaten_carb, eaten_fat)
      else
        vim.ui.input({ prompt = string.format("Grams for '%s': ", parsed.name), default = "100" }, function(g_str)
          local grams = eval_grams(g_str)
          if not grams or grams <= 0 then
            return
          end
          local factor = grams / 100
          eaten_cal = math.floor(per_cal * factor + 0.5)
          eaten_pro = math.floor(per_pro * factor + 0.5)
          eaten_carb = math.floor(per_carb * factor + 0.5)
          eaten_fat = math.floor(per_fat * factor + 0.5)
          _do_insert_food_row(bufnr, "", parsed.name, grams, eaten_cal, eaten_pro, eaten_carb, eaten_fat)
        end)
      end
    end
  end

  if initial_input then
    process_input(initial_input)
  else
    vim.ui.input({
      prompt = "Quick Food (e.g. 'Skyr 71 8.6 8.3 0.2 [150]' or 'Bar @ 60g: 220 20 15 8'): ",
    }, process_input)
  end
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
      _G.quick_add_food()
    else
      vim.ui.input({ prompt = "Grams: ", default = "100" }, function(grams_str)
        local grams = eval_grams(grams_str)
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

_G.save_row_to_food_library = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
  if not line or not line:match("^|") then
    vim.notify("[calories] Not on a table row.", vim.log.levels.WARN)
    return
  end

  local cells = parse_row_cells(line)
  table.remove(cells, 1) -- remove meal column
  if #cells < 6 then
    vim.notify("[calories] Not enough columns in this row.", vim.log.levels.WARN)
    return
  end

  local name = cells[1] or ""
  if name == "" or name:match("^TOTAL$") then
    vim.notify("[calories] No food name on this row.", vim.log.levels.WARN)
    return
  end

  local cur_g = row_tonumber(cells[2])
  local cur_cal = row_tonumber(cells[3])
  local cur_pro = row_tonumber(cells[4])
  local cur_carb = row_tonumber(cells[5])
  local cur_fat = row_tonumber(cells[6])

  local function do_save(grams)
    if not grams or grams <= 0 then
      return
    end
    local factor = 100 / grams
    local per_cal = math.floor(cur_cal * factor + 0.5)
    local per_pro = math.floor(cur_pro * factor * 10 + 0.5) / 10
    local per_carb = math.floor(cur_carb * factor * 10 + 0.5) / 10
    local per_fat = math.floor(cur_fat * factor * 10 + 0.5) / 10
    append_to_food_library(name, per_cal, per_pro, per_carb, per_fat)
  end

  if cur_g > 0 then
    do_save(cur_g)
  else
    vim.ui.input({
      prompt = string.format("Grams for '%s' (enter 100 if row is already per-100g): ", name),
      default = "100",
    }, function(g_str)
      local grams = eval_grams(g_str)
      do_save(grams)
    end)
  end
end

_G.lookup_barcode = function()
  local heading_start, bufnr = get_current_day_heading_range()
  if not heading_start then
    vim.notify("[calories] Today's entry not found. Use <leader>od to create it first.", vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = "Barcode (EAN) or search query: " }, function(input)
    if not input or input:match("^%s*$") then
      return
    end
    input = vim.trim(input)

    local is_barcode = input:match("^%d%d%d%d%d%d%d+$") ~= nil

    if is_barcode then
      vim.notify("[calories] Looking up barcode " .. input .. "...", vim.log.levels.INFO)
      local url = string.format("https://world.openfoodfacts.org/api/v2/product/%s.json", input)
      local raw =
          vim.fn.system({ "curl", "-s", "--max-time", "8", "-L", "-H", "User-Agent: MyCalorieTracker/1.0", url })
      local ok, data = pcall(vim.json.decode, raw)
      if not ok or not data or data.status ~= 1 or not data.product then
        vim.notify("[calories] Product not found for barcode: " .. input, vim.log.levels.WARN)
        return
      end

      local p = data.product
      local brand = p.brands and p.brands:match("^([^,]+)") or ""
      local name = p.product_name or p.product_name_de or p.product_name_en or "Unknown Food"
      if brand ~= "" and not name:lower():find(brand:lower(), 1, true) then
        name = brand .. " " .. name
      end

      local nut = p.nutriments or {}
      local cal = tonumber(nut["energy-kcal_100g"]) or 0
      local pro = tonumber(nut.proteins_100g) or 0
      local carb = tonumber(nut.carbohydrates_100g) or 0
      local fat = tonumber(nut.fat_100g) or 0

      local default_g = "100"
      if p.serving_quantity then
        local sq = tonumber(p.serving_quantity)
        if sq and sq > 0 then
          default_g = tostring(math.floor(sq + 0.5))
        end
      end

      vim.ui.input({
        prompt = string.format(
          "Grams for '%s' (%dc/%dp/%dcb/%df /100g): ",
          name,
          math.floor(cal + 0.5),
          math.floor(pro + 0.5),
          math.floor(carb + 0.5),
          math.floor(fat + 0.5)
        ),
        default = default_g,
      }, function(g_str)
        local grams = eval_grams(g_str)
        if not grams or grams <= 0 then
          return
        end
        local factor = grams / 100
        append_to_food_library(name, cal, pro, carb, fat)
        _do_insert_food_row(bufnr, "", name, grams, cal * factor, pro * factor, carb * factor, fat * factor)
      end)
    else
      vim.notify("[calories] Searching Open Food Facts for '" .. input .. "'...", vim.log.levels.INFO)
      local encoded = vim.uri_encode(input)
      local url = string.format(
        "https://world.openfoodfacts.org/cgi/search.pl?search_terms=%s&search_simple=1&action=process&json=1&page_size=5",
        encoded
      )
      local raw =
          vim.fn.system({ "curl", "-s", "--max-time", "8", "-L", "-H", "User-Agent: MyCalorieTracker/1.0", url })
      local ok, data = pcall(vim.json.decode, raw)
      if not ok or not data or not data.products or #data.products == 0 then
        vim.notify("[calories] No products found for: " .. input, vim.log.levels.WARN)
        return
      end

      local items = {}
      for _, p in ipairs(data.products) do
        local brand = p.brands and p.brands:match("^([^,]+)") or ""
        local name = p.product_name or p.product_name_de or p.product_name_en or "Unknown"
        if brand ~= "" and not name:lower():find(brand:lower(), 1, true) then
          name = brand .. " " .. name
        end
        local nut = p.nutriments or {}
        local cal = tonumber(nut["energy-kcal_100g"]) or 0
        local pro = tonumber(nut.proteins_100g) or 0
        local carb = tonumber(nut.carbohydrates_100g) or 0
        local fat = tonumber(nut.fat_100g) or 0
        table.insert(items, { name = name, cal = cal, pro = pro, carb = carb, fat = fat })
      end

      vim.ui.select(items, {
        prompt = "Select product:",
        format_item = function(item)
          return string.format(
            "%-32s  %3dc | %3dp | %3dcb | %3df /100g",
            item.name,
            math.floor(item.cal + 0.5),
            math.floor(item.pro + 0.5),
            math.floor(item.carb + 0.5),
            math.floor(item.fat + 0.5)
          )
        end,
      }, function(selected)
        if not selected then
          return
        end
        vim.ui.input({
          prompt = string.format("Grams for '%s': ", selected.name),
          default = "100",
        }, function(g_str)
          local grams = eval_grams(g_str)
          if not grams or grams <= 0 then
            return
          end
          local factor = grams / 100
          append_to_food_library(selected.name, selected.cal, selected.pro, selected.carb, selected.fat)
          _do_insert_food_row(
            bufnr,
            "",
            selected.name,
            grams,
            selected.cal * factor,
            selected.pro * factor,
            selected.carb * factor,
            selected.fat * factor
          )
        end)
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
    local grams = eval_grams(grams_str)
    if not grams or grams <= 0 then
      return
    end
    local factor = grams / 100
    local cal = math.floor(per_cal * factor + 0.5)
    local pro = math.floor(per_pro * factor + 0.5)
    local carb = math.floor(per_carb * factor + 0.5)
    local fat = math.floor(per_fat * factor + 0.5)

    local g_str = grams > 0 and fmt_num(grams) or ""
    local row_str =
        string.format("| %-9s | %-22s | %-4s | %4d | %3d | %4d | %3d |", "", name, g_str, cal, pro, carb, fat)

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

local function open_random_video_by_date(opts, mode)
  local query_string = opts.args or ""
  local org_api = require("orgmode.api")

  local files = org_api.load()
  local candidates = {}
  for _, file in ipairs(files) do
    local file_path = file.filename
    for _, h in ipairs(file.headlines) do
      if h.todo_type == "TODO" and has_youtube_tag(h) then
        if matches_query(h, query_string) then
          local pub_str = h:get_property("Published")
          local pub_time = parse_date(pub_str)
          table.insert(candidates, {
            headline = h,
            path = file_path,
            published = pub_time,
            pub_str = pub_str or "",
          })
        end
      end
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

vim.api.nvim_create_user_command("OrgYoutube", open_youtube_query, { nargs = "?" })
vim.api.nvim_create_user_command("OrgYoutubeRandom", open_random_video, { nargs = "?" })
vim.api.nvim_create_user_command("OrgYoutubeRandomRecent", function(opts)
  open_random_video_by_date(opts, "recent")
end, { nargs = "?" })
vim.api.nvim_create_user_command("OrgYoutubeRandomOldest", function(opts)
  open_random_video_by_date(opts, "oldest")
end, { nargs = "?" })

vim.api.nvim_create_autocmd("FileType", {
  pattern = "org",
  group = vim.api.nvim_create_augroup("orgmode_calorie_tracker", { clear = true }),
  callback = function()
    pcall(vim.cmd, "TableModeEnable")
    vim.keymap.set("n", "<leader>op", require("telescope").extensions.orgmode.refile_heading)
    vim.keymap.set("n", "<leader>os", require("telescope").extensions.orgmode.search_headings)
    vim.keymap.set("n", "<leader>oyt", ":OrgYoutube<CR>", { buffer = 0, desc = "YouTube All" })
    vim.keymap.set("n", "<leader>oys", ":OrgYoutube Duration<600<CR>", { buffer = 0, desc = "YouTube Short" })
    vim.keymap.set("n", "<leader>oyi", ":OrgYoutube Importance=5<CR>", { buffer = 0, desc = "YouTube Important" })
    vim.keymap.set("n", "<leader>oyr", ":OrgYoutubeRandom<CR>", { buffer = 0, desc = "YouTube Random" })
    vim.keymap.set("n", "<leader>oyR", ":OrgYoutubeRandom Duration<600", { buffer = 0, desc = "YouTube Random Query" })
    vim.keymap.set("n", "<leader>oyn", ":OrgYoutubeRandomRecent<CR>", { buffer = 0, desc = "YouTube Random Recent" })
    vim.keymap.set("n", "<leader>oyN", ":OrgYoutubeRandomRecent Duration<600", { buffer = 0, desc = "YouTube Random Recent Short" })
    vim.keymap.set("n", "<leader>oyo", ":OrgYoutubeRandomOldest<CR>", { buffer = 0, desc = "YouTube Random Oldest" })
    vim.keymap.set("n", "<leader>oyO", ":OrgYoutubeRandomOldest Duration<600", { buffer = 0, desc = "YouTube Random Oldest Short" })

    -- Calorie tracker keymaps — only in calories.org
    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath:match("calories%.org$") or filepath:match("calories%.org/") then
      vim.keymap.set(
        "n",
        "<leader>od",
        "<cmd>lua _G.create_calorie_day()<CR>",
        { buffer = 0, desc = "New calorie day" }
      )
      vim.keymap.set("n", "<leader>of", "<cmd>lua _G.add_food_row()<CR>", { buffer = 0, desc = "Add food" })
      vim.keymap.set("n", "<leader>oq", "<cmd>lua _G.quick_add_food()<CR>", { buffer = 0, desc = "Quick add food" })
      vim.keymap.set(
        "n",
        "<leader>ow",
        "<cmd>lua _G.save_row_to_food_library()<CR>",
        { buffer = 0, desc = "Write row to library" }
      )
      vim.keymap.set(
        "n",
        "<leader>ob",
        "<cmd>lua _G.lookup_barcode()<CR>",
        { buffer = 0, desc = "Barcode / OpenFoodFacts lookup" }
      )
      vim.keymap.set("n", "<leader>ol", "<cmd>lua _G.calc_daily_totals()<CR>", { buffer = 0, desc = "Calc totals" })
      vim.keymap.set("n", "<leader>or", "<cmd>lua _G.recalc_current_row()<CR>", { buffer = 0, desc = "Recalc row" })
      vim.keymap.set("n", "<leader>on", "<cmd>lua _G.goto_today()<CR>", { buffer = 0, desc = "Go to today" })
    end
  end,
})
