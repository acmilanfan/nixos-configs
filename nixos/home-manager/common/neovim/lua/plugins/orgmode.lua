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

local function open_youtube_query(opts)
  local query_string = opts.args or ""
  local org_api = require("orgmode.api")

  -- 1. Helper: Query Matcher
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

  -- 2. Helper: Inherited Tags
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

  -- 3. Helper: Parse Date
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

  -- 4. Load and Collect (Store Path Explicitly)
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

  -- 5. Sort (Unwrap to access properties)
  table.sort(items, function(a, b)
    local t_a = parse_date(a.headline:get_property("Published"))
    local t_b = parse_date(b.headline:get_property("Published"))
    return t_a < t_b
  end)

  -- 6. Build Quickfix List
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

vim.api.nvim_create_user_command("OrgYoutube", open_youtube_query, { nargs = "?" })

vim.api.nvim_create_autocmd("FileType", {
  pattern = "org",
  group = vim.api.nvim_create_augroup("orgmode_telescope_nvim", { clear = true }),
  callback = function()
    vim.keymap.set("n", "<leader>op", require("telescope").extensions.orgmode.refile_heading)
    vim.keymap.set("n", "<leader>os", require("telescope").extensions.orgmode.search_headings)
    vim.keymap.set("n", "<leader>oyt", ":OrgYoutube<CR>", { desc = "YouTube All" })
    vim.keymap.set("n", "<leader>oys", ":OrgYoutube Duration<600<CR>", { desc = "YouTube Short" })
    vim.keymap.set("n", "<leader>oyi", ":OrgYoutube Importance=5<CR>", { desc = "YouTube Important" })
  end,
})
