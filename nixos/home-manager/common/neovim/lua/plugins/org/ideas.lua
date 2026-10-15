local M = {}
local core = require("plugins.org.core")

local function eligible(headline)
  if headline.todo_value ~= "IDEA" or headline.todo_type ~= "TODO" or headline.is_archived then return false end
  local parent = headline
  while parent do
    if parent:get_property("PROMOTED_TO") then return false end
    parent = parent.parent
  end
  return true
end

function M.collect()
  local candidates = {}
  for _, path in ipairs(core.files("ideas")) do
    for _, headline in ipairs(core.headlines(path)) do
      if eligible(headline) then
        candidates[#candidates + 1] = {
          filename = path, lnum = headline.position.start_line, title = headline.title,
          text = "[IDEA] " .. headline.title, tags = headline.all_tags,
          reviewed = headline:get_property("REVIEWED"), headline = headline,
        }
      end
    end
  end
  return candidates
end

function M.review_items(count)
  count = count or 3
  assert(count > 0 and count == math.floor(count), "Idea count must be a positive integer")
  local items, selection = M.collect(), {}
  table.sort(items, function(a, b)
    if not a.reviewed and b.reviewed then return true end
    if a.reviewed and not b.reviewed then return false end
    if a.reviewed ~= b.reviewed then return (a.reviewed or "") < (b.reviewed or "") end
    return a.filename .. ":" .. a.lnum < b.filename .. ":" .. b.lnum
  end)
  if #items > 0 and not items[1].reviewed then selection[#selection + 1] = table.remove(items, 1) end
  if #selection < count then
    for i, item in ipairs(items) do
      if item.reviewed then selection[#selection + 1] = table.remove(items, i) break end
    end
  end
  while #items > 0 and #selection < count do selection[#selection + 1] = table.remove(items, math.random(#items)) end
  return selection
end

function M.promote(path, lnum, kind, name)
  assert(kind == "task" or kind == "project", "Promote to task or project")
  local h = assert(require("orgmode.api").load(path):get_headline_on_line(lnum), "No idea at cursor")
  assert(eligible(h), "Choose an unfinished IDEA outside a promoted subtree")
  core.save(path)
  local original = core.read(path)
  local finish = #original
  for _, line in ipairs(core.active_lines(original)) do
    local stars = line.text:match("^(%*+)%s")
    if line.lnum > lnum and stars and #stars <= h.level then finish = line.lnum - 1 break end
  end
  local source_id = h:get_property("ID") or core.new_id()
  local source_selector = "::#" .. (h:get_property("CUSTOM_ID") or source_id)
  local destination_id = core.new_id()
  local body = vim.list_slice(original, lnum + 1, finish)
  local tags = vim.deepcopy(h.tags)
  for _, tag in ipairs({ "this", "next", "recurring" }) do
    if vim.tbl_contains(h.all_tags, tag) and not vim.tbl_contains(tags, tag) then tags[#tags + 1] = tag end
  end
  local target, before, created, lines
  if kind == "project" then
    name = name or h.title
    target = core.root() .. "/life/projects/planning/" .. core.slug(name) .. ".org"
    assert(not vim.uv.fs_stat(target), "Project already exists: " .. target)
  else
    target = core.root() .. "/life/tasks/tasks.org"
    assert(path ~= target, "The idea is already in the task destination file")
    core.save(target)
    before = vim.fn.filereadable(target) == 1 and core.read(target) or {}
    lines = vim.deepcopy(before)
    if #lines > 0 then lines[#lines + 1] = "" end
    local heading_line = #lines + 1
    lines[#lines + 1] = "* TODO " .. h.title .. (#tags > 0 and " :" .. table.concat(tags, ":") .. ":" or "")
    local copied = core.rewrite_links(core.relevel(body, 1 - h.level), path, target, "", "")
    vim.list_extend(lines, copied)
    lines = core.with_property(lines, heading_line, "ID", destination_id)
    lines = core.with_property(lines, heading_line, "CUSTOM_ID", destination_id)
    lines = core.with_property(lines, heading_line, "SOURCE_ID", source_id)
    lines = core.with_property(lines, heading_line, "ORIGIN", core.link(target, path, h.title, source_selector))
  end
  local promoted = core.with_property(original, lnum, "ID", source_id)
  promoted = core.with_property(promoted, lnum, "CUSTOM_ID", source_selector:sub(4))
  promoted = core.with_property(promoted, lnum, "REVIEWED", os.date("[%Y-%m-%d %a]"))
  promoted = core.with_property(promoted, lnum, "PROMOTED_TO", core.link(path, target, h.title, "::#" .. destination_id))
  local ok, err = pcall(function()
    if kind == "project" then
      local reference = { "** Original idea" }
      vim.list_extend(reference, core.rewrite_links(core.relevel(body, 2 - h.level), path, target, "", ""))
      reference = core.with_property(reference, 1, "ID", nil)
      reference = core.with_property(reference, 1, "CUSTOM_ID", nil)
      local origin = core.link(target, path, h.title, source_selector)
      require("plugins.org.projects").create(name, {
        title = h.title, reference = origin, body = reference, tags = tags, source_id = source_id, id = destination_id,
      })
      created = true
    elseif not vim.uv.fs_stat(target) then
      core.create_file(target, lines)
      created = true
    else
      core.write(target, lines)
    end
    core.write(path, promoted)
  end)
  if not ok then
    if created then
      assert(vim.uv.fs_unlink(target), "Could not remove failed promotion: " .. target)
      local buf = vim.fn.bufnr(target)
      if buf ~= -1 then vim.api.nvim_buf_delete(buf, { force = true }) end
    elseif before then core.restore(target, before) end
    core.restore(path, original)
    error("Promotion rolled back: " .. tostring(err))
  end
  core.refresh()
  return target
end

function M.random_items(count)
  count = (count == nil or count == "") and 3 or count
  count = assert(tonumber(count), "Idea count must be a positive integer")
  assert(count > 0 and count == math.floor(count), "Idea count must be a positive integer")
  local candidates = M.collect()
  local selection = {}
  local pick_count = math.min(count, #candidates)
  for _ = 1, pick_count do
    local idx = math.random(#candidates)
    table.insert(selection, table.remove(candidates, idx))
  end
  return selection
end

local function open_random_ideas(opts)
  local selection = M.random_items(opts.args)
  core.quickfix("Random ideas", vim.tbl_map(function(item)
    return { filename = item.filename, lnum = item.lnum, text = item.text }
  end, selection))
  print(string.format("Selected %d random ideas from backlog for review", #selection))
end

function M.setup_commands()
  core.command("OrgIdeaRandom", open_random_ideas, { nargs = "?" })
  core.command("OrgIdeaReview", function(opts)
    local items = M.review_items(opts.args ~= "" and assert(tonumber(opts.args), "Use a positive idea count") or 3)
    core.quickfix("Idea review — never reviewed / oldest reviewed / random", vim.tbl_map(function(item)
      return { filename = item.filename, lnum = item.lnum, text = item.text .. " | reviewed: " .. (item.reviewed or "never") }
    end, items))
  end, { nargs = "?" })
  core.command("OrgIdeaReviewed", function()
    local h = core.current_headline()
    assert(h.todo_value == "IDEA", "Choose an IDEA")
    core.set_property(h.file.filename, h.position.start_line, "REVIEWED", os.date("[%Y-%m-%d %a]"))
  end)
  core.command("OrgIdeaDrop", function()
    local h = core.current_headline()
    assert(h.todo_value == "IDEA", "Choose an IDEA")
    local lines = core.read(h.file.filename)
    lines[h.position.start_line] = lines[h.position.start_line]:gsub("^(%*+%s+)IDEA%s", "%1SKIP ")
    lines = core.with_property(lines, h.position.start_line, "REVIEWED", os.date("[%Y-%m-%d %a]"))
    core.write(h.file.filename, lines)
  end)
  core.command("OrgIdeaPromote", function(opts)
    local h = core.current_headline()
    local kind, name = opts.args:match("^(%S+)%s*(.*)$")
    if kind then
      local target = M.promote(h.file.filename, h.position.start_line, kind, name ~= "" and name or nil)
      vim.notify("Idea promoted to " .. target)
      return
    end
    vim.ui.select({ "task", "project" }, { prompt = "Promote idea to:" }, function(choice)
      if not choice then return end
      local ok, target = pcall(M.promote, h.file.filename, h.position.start_line, choice)
      vim.notify(tostring(target), ok and vim.log.levels.INFO or vim.log.levels.ERROR)
    end)
  end, { nargs = "*" })
end

function M.setup_keymaps()
  vim.keymap.set("n", "<leader>oir", ":OrgIdeaRandom<CR>", { desc = "Random Ideas Review" })
  vim.keymap.set("n", "<leader>oiv", "<cmd>OrgIdeaReview<CR>", { desc = "Mixed ideas review" })
end

function M.setup()
  M.setup_commands()
  M.setup_keymaps()
end

return M
