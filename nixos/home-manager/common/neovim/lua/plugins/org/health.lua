local core = require("plugins.org.core")
local M = {}

function M.check_links(path)
  local items = {}
  for _, link in ipairs(core.links(core.read(path))) do
    local target = core.local_target(path, link.target)
    if target and not vim.uv.fs_stat(target) then
      items[#items + 1] = { filename = path, lnum = link.lnum, type = "W", text = "Missing link: " .. link.target }
    end
  end
  return items
end

function M.unfinished(path)
  local issues = {}
  for _, h in ipairs(core.headlines(path)) do
    if h.todo_type == "TODO" and not h.is_archived then
      issues[#issues + 1] = { filename = path, lnum = h.position.start_line, type = "W", text = "Open task: " .. h.title }
    end
  end
  local file = require("orgmode").files:get(path)
  local lines, active = core.read(path), {}
  for _, line in ipairs(core.active_lines(lines)) do active[line.lnum] = true end
  local function visit(node)
    if node:type() == "listitem" then
      local checkbox = node:field("checkbox")[1]
      if checkbox then
        local row, col = checkbox:range()
        local h = file:get_closest_headline_or_nil({ row + 1, col })
        local text = file:get_node_text(checkbox)
        if active[row + 1] and text ~= "[X]" and text ~= "[x]" and not (h and h:is_archived()) then
          issues[#issues + 1] = { filename = path, lnum = row + 1, type = "W", text = "Unchecked item: " .. vim.trim(lines[row + 1]) }
        end
      end
    end
    for child in node:iter_children() do visit(child) end
  end
  visit(file.root)
  table.sort(issues, function(a, b) return a.lnum < b.lnum end)
  return issues
end

function M.check_project(path, stage)
  if stage == "finished" then return M.unfinished(path) end
  local issues = {}
  if stage ~= "current" then return issues end
  local summary = require("plugins.org.projects").summary(path, stage)
  local function issue(text)
    issues[#issues + 1] = { filename = path, lnum = summary.lnum, type = "W", text = text }
  end
  local metadata = table.concat(core.read(path), "\n")
  if not metadata:match("#%+TITLE:") then issue("Missing #+TITLE") end
  if not metadata:match("#%+CATEGORY:") then issue("Missing #+CATEGORY") end
  if not metadata:match("#%+FILETAGS:[^\n]*:project:") then issue("Missing project file tag") end
  if summary.outcome == "" then issue("Missing concrete Outcome") end
  if #summary.actions == 0 then issue("Missing next_action on an unfinished task") end
  if #summary.actions > 1 then issue("Multiple next_action tasks; choose the immediate step") end
  if summary.reviewed == "never" then issue("Project has not been marked reviewed") end
  return issues
end

function M.collect(scope)
  scope = scope or "all"
  assert(scope == "all" or scope == "links" or scope == "projects", "Use OrgCheck [links|projects|all]")
  local issues = {}
  if scope ~= "projects" then
    for _, path in ipairs(core.files("all")) do vim.list_extend(issues, M.check_links(path)) end
  end
  if scope ~= "links" then
    for _, stage in ipairs({ "current", "finished" }) do
      for _, path in ipairs(core.files(stage)) do vim.list_extend(issues, M.check_project(path, stage)) end
    end
    for _, path in ipairs(core.files("knowledge")) do
      for _, line in ipairs(core.active_lines(core.read(path))) do
        if line.text:match("^#+%s+%S") then
          issues[#issues + 1] = { filename = path, lnum = line.lnum, type = "W", text = "Markdown heading in Org file" }
        end
      end
    end
  end
  return issues
end

function M.setup()
  core.command("OrgCheck", function(opts) core.quickfix("Org health", M.collect(opts.args ~= "" and opts.args or nil)) end,
    { nargs = "?", complete = function() return { "all", "links", "projects" } end })
  vim.keymap.set("n", "<leader>ohc", "<cmd>OrgCheck<CR>", { desc = "Check Org links and projects" })
end

return M
