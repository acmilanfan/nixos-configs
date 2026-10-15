local core = require("plugins.org.core")
local M = {}
local categories = { "tech", "principles", "finance", "health", "travel", "ideas", "projects", "year" }

function M.create(category, title)
  assert(vim.tbl_contains(categories, category), "Choose a note category: " .. table.concat(categories, ", "))
  local slug = core.slug(title)
  local path = core.root() .. "/life/notes/" .. category .. "/" .. slug .. ".org"
  local id = core.new_id()
  core.create_file(path, { "#+TITLE: " .. title, "#+CATEGORY: " .. category, "#+FILETAGS: :reference:" .. category .. ":",
    "", "* " .. title, ":PROPERTIES:", ":ID: " .. id, ":CUSTOM_ID: " .. id, ":CREATED: " .. os.date("[%Y-%m-%d %a]"), ":END:", "" })
  return path
end

function M.collect(scope)
  local entries = {}
  for _, path in ipairs(core.files(scope or "knowledge")) do
    local title = vim.fn.fnamemodify(path, ":t:r")
    for _, line in ipairs(core.read(path)) do title = line:match("^#%+TITLE:%s*(.+)") or title end
    entries[#entries + 1] = { filename = path, lnum = 1, title = title,
      text = "[file] " .. core.relative(core.root() .. "/life/index.org", path) .. " — " .. title, file_root = true }
    for _, h in ipairs(core.headlines(path)) do
      entries[#entries + 1] = { filename = path, lnum = h.position.start_line, title = h.title,
        text = core.relative(core.root() .. "/life/index.org", path) .. " — " .. (h.todo_value or "") .. " " .. h.title,
        file_root = false }
    end
  end
  return entries
end

function M.open()
  core.pick("Org knowledge — notes and project history", M.collect(), function(item)
    vim.cmd("edit " .. vim.fn.fnameescape(item.filename))
    vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
    vim.cmd("normal! zv")
  end)
end

function M.insert_link()
  local buf, source, cursor = vim.api.nvim_get_current_buf(), vim.api.nvim_buf_get_name(0), vim.api.nvim_win_get_cursor(0)
  assert(vim.bo[buf].filetype == "org" and source ~= "", "Insert knowledge links from a named Org buffer")
  local ns = vim.api.nvim_create_namespace("org_knowledge_link")
  local mark = vim.api.nvim_buf_set_extmark(buf, ns, cursor[1] - 1, cursor[2], {})
  core.pick("Link Org knowledge", M.collect(), function(item)
    assert(vim.api.nvim_buf_is_valid(buf), "Source buffer was closed")
    local selector = not item.file_root and core.heading_selector(item.filename, item.lnum) or nil
    vim.api.nvim_set_current_buf(buf)
    local position = vim.api.nvim_buf_get_extmark_by_id(buf, ns, mark, {})
    vim.api.nvim_buf_del_extmark(buf, ns, mark)
    vim.api.nvim_win_set_cursor(0, { position[1] + 1, position[2] })
    vim.api.nvim_put({ core.link(source, item.filename, item.title, selector) }, "c", true, true)
  end)
end

function M.refile_entries(source)
  return vim.tbl_filter(function(item)
    if item.filename ~= source.file.filename then return true end
    return not item.file_root and (item.lnum < source.position.start_line or item.lnum > source.position.end_line)
  end, M.collect("refile"))
end

-- Save the destination before removing the source; Orgmode's built-in refile
-- suppresses some write errors, so this operation owns its transaction.
function M.refile_to(source, item)
  local source_path, target = source.file.filename, item.filename
  local capture_buf = vim.fn.bufnr(source_path)
  local capture = capture_buf ~= -1 and vim.b[capture_buf].org_capture
  if not capture then core.save(source_path) end
  core.save(target)
  source = assert(require("orgmode.api").load(source_path):get_headline_on_line(source.position.start_line), "Source changed")
  local source_lines, target_lines = core.read(source_path), core.read(target)
  local first, last = source.position.start_line, source.position.end_line
  local insertion, level = #target_lines, 1
  if not item.file_root then
    local parent = assert(require("orgmode.api").load(target):get_headline_on_line(item.lnum), "Destination changed")
    insertion, level = parent.position.end_line, parent.level + 1
  end
  if source_path == target then
    assert(not (item.lnum >= first and item.lnum <= last) or item.file_root, "Cannot refile a heading into its own subtree")
  end
  local moved = core.relevel(vim.list_slice(source_lines, first, last), level - source.level)
  if not capture then moved = core.rewrite_links(moved, source_path, target, "", "") end
  local remaining = vim.list_slice(source_lines, 1, first - 1)
  vim.list_extend(remaining, vim.list_slice(source_lines, last + 1, #source_lines))
  local destination = target_lines
  if source_path == target then
    destination = remaining
    if insertion >= last then insertion = insertion - (last - first + 1) end
  end
  local result = vim.list_slice(destination, 1, insertion)
  if #result > 0 and result[#result] ~= "" then result[#result + 1] = "" end
  vim.list_extend(result, moved)
  vim.list_extend(result, vim.list_slice(destination, insertion + 1, #destination))
  local ok, err = pcall(function()
    core.write(target, result)
    if source_path ~= target and not capture then core.write(source_path, remaining) end
  end)
  if not ok then
    core.restore(target, target_lines)
    if source_path ~= target and not capture then core.restore(source_path, source_lines) end
    error("Refile rolled back: " .. tostring(err))
  end
  if capture then require("orgmode").capture:kill(false, vim.b[capture_buf].org_capture_window_id) end
  core.refresh()
  return true
end

function M.refile()
  local source = core.current_headline()
  local entries = M.refile_entries(source)
  core.pick("Refile — notes and project history", entries, function(item)
    M.refile_to(source, item)
  end)
end

function M.setup()
  core.command("OrgNoteNew", function(opts)
    local category, title = opts.args:match("^(%S+)%s+(.+)$")
    if category then vim.cmd("edit " .. vim.fn.fnameescape(M.create(category, title))) return end
    vim.ui.select(categories, { prompt = "Note category:" }, function(choice)
      if not choice then return end
      vim.ui.input({ prompt = "Note title:" }, function(input)
        if not input or vim.trim(input) == "" then return end
        local ok, path = pcall(M.create, choice, input)
        if ok then vim.cmd("edit " .. vim.fn.fnameescape(path)) else vim.notify(tostring(path), vim.log.levels.ERROR) end
      end)
    end)
  end, { nargs = "*" })
  core.command("OrgKnowledge", M.open)
  core.command("OrgNoteLink", M.insert_link)
  core.command("OrgKnowledgeRefile", M.refile)
  vim.keymap.set("n", "<leader>onk", "<cmd>OrgKnowledge<CR>", { desc = "Search Org knowledge" })
  vim.keymap.set("n", "<leader>onl", "<cmd>OrgNoteLink<CR>", { desc = "Insert knowledge link" })
  vim.keymap.set("n", "<leader>onn", "<cmd>OrgNoteNew<CR>", { desc = "New categorized note" })
  local ok, builtin = pcall(require, "telescope.builtin")
  if ok then
    vim.keymap.set("n", "<leader>onf", function()
      builtin.find_files({ prompt_title = "Find Notes", cwd = core.root() .. "/life/notes" })
    end, { desc = "Find Notes" })
    vim.keymap.set("n", "<leader>ong", function()
      builtin.live_grep({ prompt_title = "Grep in Notes", cwd = core.root() .. "/life/notes" })
    end, { desc = "Grep in Notes" })
  end
end

return M
