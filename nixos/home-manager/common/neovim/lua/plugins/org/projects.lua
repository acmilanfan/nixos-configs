local core = require("plugins.org.core")
local M = {}
local stages = { current = true, planning = true, finished = true, discard = true }

function M.stage(path)
  local prefix = core.root() .. "/life/projects/"
  assert(path:sub(1, #prefix) == prefix, "Current file is not in the configured projects directory")
  local stage, name = path:sub(#prefix + 1):match("^([^/]+)/([^/]+%.org)$")
  assert(stages[stage] and name, "Open a project in a lifecycle folder (not the template)")
  return stage, name
end

function M.summary(path, stage)
  local lines, headlines = core.read(path), core.headlines(path)
  local item = { filename = path, lnum = 1, stage = stage, title = vim.fn.fnamemodify(path, ":t:r"),
    open_count = 0, actions = {}, outcome = "", reviewed = "never" }
  for _, line in ipairs(lines) do
    local title = line:match("^#%+TITLE:%s*(.+)")
    if title then item.title = title end
  end
  local root = headlines[1]
  if root then
    item.lnum, item.reviewed = root.position.start_line, root:get_property("REVIEWED") or "never"
  end
  for _, h in ipairs(headlines) do
    if h.todo_type == "TODO" and not h.is_archived then
      item.open_count = item.open_count + 1
      if vim.tbl_contains(h.tags, "next_action") then item.actions[#item.actions + 1] = h end
    end
    if h.title:match("^Outcome") then
      for lnum = h.position.start_line + 1, #lines do
        if lines[lnum]:match("^%*+%s") then break end
        local outcome = vim.trim(lines[lnum]):gsub("^%- %[[ Xx%-]%]%s*", ""):gsub("^%-%s*", "")
        if outcome ~= "" and item.outcome == "" then item.outcome = outcome end
      end
    end
  end
  item.next_action = item.actions[1] and item.actions[1].title or "MISSING"
  item.text = string.format("[%s] %s | %d open | next: %s | reviewed: %s | outcome: %s",
    stage, item.title, item.open_count, item.next_action, item.reviewed, item.outcome)
  return item
end

function M.collect(stage)
  local items = {}
  for _, name in ipairs(stage == "all" and { "current", "planning", "finished", "discard" } or { stage or "current", "planning" }) do
    for _, path in ipairs(core.files(name)) do items[#items + 1] = M.summary(path, name) end
    if stage and stage ~= "all" then break end
  end
  table.sort(items, function(a, b)
    if a.stage ~= b.stage then return a.stage == "current" end
    if (a.next_action == "MISSING") ~= (b.next_action == "MISSING") then return a.next_action == "MISSING" end
    if a.reviewed ~= b.reviewed then return a.reviewed < b.reviewed end
    return a.title < b.title
  end)
  return items
end

function M.set_next(path, lnum)
  M.stage(path)
  local selected = assert(require("orgmode.api").load(path):get_headline_on_line(lnum), "No task at cursor")
  assert(selected.todo_type == "TODO", "Choose an unfinished task")
  local lines = core.read(path)
  for _, h in ipairs(core.headlines(path)) do
    local tags = vim.tbl_filter(function(tag) return tag ~= "next_action" end, h.tags)
    if h.position.start_line == lnum then tags[#tags + 1] = "next_action" end
    if not vim.deep_equal(tags, h.tags) then
      local line = lines[h.position.start_line]:gsub("%s+:[%w_@#%%:]+:%s*$", "")
      lines[h.position.start_line] = line .. (#tags > 0 and " :" .. table.concat(tags, ":") .. ":" or "")
    end
  end
  core.write(path, lines)
  core.refresh()
end

function M.create(name, options)
  options = options or {}
  local slug = core.slug(name)
  local stage = options.stage or "planning"
  assert(stages[stage], "Unknown project stage")
  local path = core.root() .. "/life/projects/" .. stage .. "/" .. slug .. ".org"
  local title = options.title or slug:gsub("%-", " ")
  local template = core.root() .. "/life/projects/template.org"
  local lines = vim.fn.filereadable(template) == 1 and core.read(template) or {
    "#+TITLE: Project Title", "#+CATEGORY: Project", "#+FILETAGS: :project:", "", "* Project Title",
    "", "** Outcome", "- [ ] Describe the concrete completion result.", "", "** Tasks",
    "*** TODO Choose the first concrete action and acceptance criteria :next_action:", "", "** Notes & Reference",
  }
  for i, line in ipairs(lines) do
    if line:match("^#%+CATEGORY:") then lines[i] = "#+CATEGORY: " .. title
    else lines[i] = line:gsub("Project Title", function() return title end) end
  end
  if options.reference then
    lines[#lines + 1] = "- Origin: " .. options.reference
    for _, line in ipairs(options.body or {}) do lines[#lines + 1] = line end
  end
  local first
  for i, line in ipairs(lines) do if line:match("^%*%s") then first = i break end end
  assert(first, "Project template needs a top-level heading")
  local id = options.id or core.new_id()
  lines = core.with_property(lines, first, "ID", id)
  lines = core.with_property(lines, first, "CUSTOM_ID", id)
  if options.source_id then lines = core.with_property(lines, first, "SOURCE_ID", options.source_id) end
  if options.tags then
    local tags = { "project" }
    for _, tag in ipairs(options.tags) do if not vim.tbl_contains(tags, tag) then tags[#tags + 1] = tag end end
    lines[first] = lines[first]:gsub("%s+:[%w_@#%%:]+:%s*$", "") .. " :" .. table.concat(tags, ":") .. ":"
  end
  core.create_file(path, lines)
  core.refresh()
  return path
end

function M.move(target_stage)
  assert(stages[target_stage], "Unknown stage")
  local source = vim.api.nvim_buf_get_name(0)
  local stage, name = M.stage(source)
  assert(stage ~= target_stage, "Project is already in " .. target_stage)
  local unfinished = require("plugins.org.health").unfinished(source)
  if target_stage == "finished" and #unfinished > 0 then
    core.quickfix("Unfinished project work — refile it before finishing", unfinished)
    return false
  end
  local replacement = core.read(source)
  local root = assert(core.headlines(source)[1], "Project has no root heading")
  if target_stage == "discard" then
    local reason = vim.fn.input("Reason for discarding (empty cancels): ")
    if vim.trim(reason) == "" then return false end
    replacement = core.with_property(replacement, root.position.start_line, "DISCARD_REASON", reason)
  end
  local destination = core.root() .. "/life/projects/" .. target_stage .. "/" .. name
  if target_stage == "finished" or target_stage == "discard" then
    replacement = core.with_property(replacement, root.position.start_line,
      target_stage == "finished" and "COMPLETED" or "DISCARDED", os.date("[%Y-%m-%d %a]"))
  end
  core.move_file(source, destination, replacement)
  vim.notify("Project moved to " .. target_stage .. "/" .. name)
  return true
end

function M.setup_commands()
  core.command("OrgProjectNew", function(opts)
    local name = opts.args ~= "" and opts.args or vim.fn.input("Project name: ")
    if vim.trim(name) ~= "" then vim.cmd("edit " .. vim.fn.fnameescape(M.create(name))) end
  end, { nargs = "?" })
  for command, stage in pairs({ Activate = "current", Plan = "planning", Finish = "finished", Discard = "discard" }) do
    core.command("OrgProject" .. command, function() M.move(stage) end)
  end
  core.command("OrgProjectReview", function(opts)
    local items = vim.tbl_map(function(item)
      return { filename = item.filename, lnum = item.lnum, text = item.text }
    end, M.collect(opts.args ~= "" and opts.args or nil))
    core.quickfix("Project review — outcomes, next actions and review dates", items)
  end, { nargs = "?", complete = function() return { "current", "planning", "all" } end })
  core.command("OrgProjectReviewed", function()
    local path = vim.api.nvim_buf_get_name(0)
    M.stage(path)
    core.set_property(path, core.headlines(path)[1].position.start_line, "REVIEWED", os.date("[%Y-%m-%d %a]"))
  end)
  core.command("OrgProjectNext", function()
    local h = core.current_headline()
    M.set_next(h.file.filename, h.position.start_line)
  end)
end

function M.setup_keymaps()
  local ok, builtin = pcall(require, "telescope.builtin")
  if ok then
    vim.keymap.set("n", "<leader>opc", function()
      builtin.find_files({ prompt_title = "Current Projects", cwd = core.root() .. "/life/projects/current" })
    end, { desc = "Find Current Projects" })
    vim.keymap.set("n", "<leader>opp", function()
      builtin.find_files({ prompt_title = "Planning Projects", cwd = core.root() .. "/life/projects/planning" })
    end, { desc = "Find Planning Projects" })
  end
  vim.keymap.set("n", "<leader>opr", "<cmd>OrgProjectReview<CR>", { desc = "Review projects" })
end

function M.setup()
  M.setup_commands()
  M.setup_keymaps()
end

return M
