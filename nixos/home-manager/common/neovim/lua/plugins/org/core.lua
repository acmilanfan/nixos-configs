local M = {}

function M.root()
  return vim.fs.normalize(vim.fn.expand(vim.g.org_root or "~/org"))
end

-- Path-prefix containment; a bare substring test would also match sibling names (consume vs consumer-service).
function M.within(path, dir)
  path, dir = vim.fs.normalize(path), vim.fs.normalize(dir)
  return path == dir or vim.startswith(path, dir .. "/")
end

function M.paths(scope)
  if scope == "refile" then
    return vim.list_extend(M.paths("execution"), M.paths("knowledge"))
  end
  local life = M.root() .. "/life"
  local scopes = {
    execution = { "/tasks/*.org", "/work/*.org", "/projects/current/*.org", "/refile.org",
      "/1refile_mobile.org", "/dump.org", "/checklists/*.org" },
    ideas = { "/notes/ideas/**/*.org" },
    current = { "/projects/current/*.org" },
    planning = { "/projects/planning/*.org" },
    finished = { "/projects/finished/*.org" },
    discard = { "/projects/discard/*.org" },
    knowledge = { "/notes/**/*.org", "/projects/current/*.org", "/projects/planning/*.org",
      "/projects/finished/*.org", "/projects/discard/*.org" },
    all = { "/**/*.org", "/**/*.org_archive" },
  }
  assert(scopes[scope], "Unknown Org scope: " .. tostring(scope))
  return vim.tbl_map(function(path) return life .. path end, scopes[scope])
end

function M.files(scope)
  local files, seen = {}, {}
  for _, pattern in ipairs(M.paths(scope)) do
    for _, path in ipairs(vim.fn.glob(pattern, false, true)) do
      path = vim.fs.normalize(path)
      if vim.fn.filereadable(path) == 1 and not seen[path] then
        files[#files + 1], seen[path] = path, true
      end
    end
  end
  table.sort(files)
  return files
end

function M.read(path)
  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  end
  return vim.fn.readfile(path)
end

function M.headlines(path)
  return require("orgmode.api").load(path).headlines
end

function M.current_headline()
  assert(vim.bo.filetype == "org", "Open an Org file first")
  return assert(require("orgmode.api").current():get_closest_headline(), "Place the cursor in an Org heading")
end

function M.save(path)
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    assert(not vim.bo[buf].readonly, "Cannot save readonly buffer: " .. path)
    if vim.bo[buf].modified then
      vim.api.nvim_buf_call(buf, function() vim.cmd("silent write") end)
    end
    assert(not vim.bo[buf].modified, "Write did not save the buffer: " .. path)
    local disk, contents = vim.fn.readfile(path), M.read(path)
    local empty = #disk == 0 and (#contents == 0 or (#contents == 1 and contents[1] == ""))
    assert(empty or vim.deep_equal(disk, contents), "Saved contents differ from the buffer: " .. path)
  end
end

function M.write(path, lines)
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    assert(not vim.bo[buf].readonly, "Cannot write readonly buffer: " .. path)
    local current, first, last = M.read(path), 0, 0
    while first < #current and first < #lines and current[first + 1] == lines[first + 1] do first = first + 1 end
    while last < #current - first and last < #lines - first and current[#current - last] == lines[#lines - last] do last = last + 1 end
    if first < #current or first < #lines then
      vim.api.nvim_buf_set_lines(buf, first, #current - last, false, vim.list_slice(lines, first + 1, #lines - last))
    end
    M.save(path)
  else
    assert(vim.fn.writefile(lines, path) == 0, "Failed to write " .. path)
  end
end

function M.restore(path, lines)
  assert(vim.fn.writefile(lines, path) == 0, "Could not restore " .. path)
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modified = false
  end
end

function M.relevel(lines, delta)
  local result = vim.deepcopy(lines)
  for _, line in ipairs(M.active_lines(lines)) do
    local stars, rest = line.text:match("^(%*+)(%s.*)$")
    if stars then
      assert(#stars + delta > 0, "Cannot promote a heading above the file root")
      result[line.lnum] = string.rep("*", #stars + delta) .. rest
    end
  end
  return result
end

function M.new_id()
  local id = require("orgmode.org.id").new()
  assert(id ~= "", "Could not generate Org ID")
  return id
end

function M.slug(name)
  name = vim.trim(name or ""):gsub("%.org$", "")
  assert(name ~= "" and not name:find("[/\\%c]") and not name:find("..", 1, true), "Use a plain name, without paths or '..'")
  local slug = name:lower():gsub("%s+", "-"):gsub("[^%w_-]", ""):gsub("%-+", "-")
  assert(slug ~= "", "Name must contain letters or numbers")
  return slug
end

-- Exclusive creation keeps commands from overwriting existing notes/projects.
function M.create_file(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local fd, err = vim.uv.fs_open(path, "wx", 420)
  assert(fd, err or ("File already exists: " .. path))
  local text = table.concat(lines, "\n") .. "\n"
  local written, write_err = vim.uv.fs_write(fd, text, 0)
  vim.uv.fs_close(fd)
  if written ~= #text then
    vim.uv.fs_unlink(path)
    error(write_err or ("Incomplete write: " .. path))
  end
  return path
end

function M.set_property(path, lnum, key, value)
  assert(require("orgmode.api").load(path):get_headline_on_line(lnum), "Heading no longer exists")
  M.write(path, M.with_property(M.read(path), lnum, key, value))
end

-- Pure drawer update, used to stage metadata before a multi-file operation.
function M.with_property(lines, lnum, key, value)
  lines = vim.deepcopy(lines)
  local start = lnum + 1
  while lines[start] and lines[start]:match("^%s*[A-Z]+:%s*[%[<]") do start = start + 1 end
  if not (lines[start] or ""):match("^%s*:PROPERTIES:%s*$") then
    if not value then return lines end
    table.insert(lines, start, ":PROPERTIES:")
    table.insert(lines, start + 1, ":" .. key .. ": " .. value)
    table.insert(lines, start + 2, ":END:")
    return lines
  end
  for i = start + 1, #lines do
    if lines[i]:match("^%s*:" .. key .. ":") then
      if value then lines[i] = ":" .. key .. ": " .. value else table.remove(lines, i) end
      return lines
    end
    if lines[i]:match("^%s*:END:%s*$") then
      if value then table.insert(lines, i, ":" .. key .. ": " .. value) end
      return lines
    end
  end
  error("Unterminated property drawer")
end

function M.refresh()
  local orgmode = require("orgmode")
  local instances = { orgmode.files }
  for _, files in pairs(require("orgmode.files").cached_instances) do instances[#instances + 1] = files end
  for _, files in ipairs(instances) do
    files.files, files.all_files, files.load_state = {}, {}, nil
    files:load(true):wait()
  end
end

function M.relative(source, destination)
  local from = vim.split(vim.fn.fnamemodify(source, ":h"), "/", { trimempty = true })
  local to = vim.split(destination, "/", { trimempty = true })
  local common = 0
  while from[common + 1] and from[common + 1] == to[common + 1] do common = common + 1 end
  local parts = {}
  for _ = common + 1, #from do parts[#parts + 1] = ".." end
  for i = common + 1, #to do parts[#parts + 1] = to[i] end
  return table.concat(parts, "/")
end

function M.link(source, destination, title, selector)
  return "[[file:" .. M.relative(source, destination) .. (selector or "") .. "][" .. title:gsub("[%[%]\r\n]", "") .. "]]"
end

function M.heading_selector(path, lnum)
  local h = assert(require("orgmode.api").load(path):get_headline_on_line(lnum), "Heading no longer exists")
  local id = h:get_property("CUSTOM_ID")
  if not id then
    id = h:get_property("ID") or M.new_id()
    M.set_property(path, lnum, "CUSTOM_ID", id)
  end
  return "::#" .. id
end

function M.pick(title, items, callback)
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    vim.ui.select(items, { prompt = title, format_item = function(item) return item.text end }, function(item)
      if item then callback(item) end
    end)
    return
  end
  local actions, state = require("telescope.actions"), require("telescope.actions.state")
  local config = require("telescope.config").values
  pickers.new({}, {
    prompt_title = title,
    finder = require("telescope.finders").new_table({ results = items, entry_maker = function(item)
      return { value = item, display = item.text, ordinal = item.text, filename = item.filename,
        path = item.filename, lnum = item.lnum }
    end }),
    sorter = config.generic_sorter({}), previewer = config.grep_previewer({}),
    attach_mappings = function(buf)
      actions.select_default:replace(function()
        local selection = state.get_selected_entry()
        actions.close(buf)
        if selection then
          local success, err = pcall(callback, selection.value)
          if not success then vim.notify(tostring(err), vim.log.levels.ERROR) end
        end
      end)
      return true
    end,
  }):find()
end

function M.rewrite_links(lines, source, new_source, old_target, new_target)
  local result = vim.deepcopy(lines)
  for _, line in ipairs(M.active_lines(lines)) do
    result[line.lnum] = line.text:gsub("(%[%[)([^%]]+)(%])", function(open, target, close)
      local destination, suffix = M.local_target(source, target)
      if not destination then return open .. target .. close end
      if destination == old_target then destination = new_target end
      if source == new_source and destination ~= new_target then return open .. target .. close end
      local explicit = target:sub(1, 5) == "file:"
      local raw = explicit and target:sub(6) or target
      local absolute = raw:sub(1, 1) == "/" or raw:sub(1, 1) == "~"
      local replacement = absolute and destination or M.relative(new_source, destination)
      return open .. (explicit and "file:" or "") .. replacement .. suffix .. close
    end)
  end
  return result
end

-- Preflight every referencing buffer; roll back disk and buffer contents on a failed write.
function M.move_file(source, destination, replacement)
  assert(source ~= destination, "File is already in that stage")
  assert(not vim.uv.fs_stat(destination) and vim.fn.bufnr(destination) == -1, "Destination already exists: " .. destination)
  local snapshots, updates = {}, {}
  for _, path in ipairs(M.files("all")) do
    local original = M.read(path)
    local new_path = path == source and destination or path
    local changed = M.rewrite_links(path == source and (replacement or original) or original, path, new_path, source, destination)
    if path == source or not vim.deep_equal(original, changed) then
      local buf = vim.fn.bufnr(path)
      if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
        assert(not vim.bo[buf].readonly, "Readonly referencing buffer: " .. path)
        assert(path == source or not vim.bo[buf].modified, "Save referencing buffer before moving: " .. path)
      end
      snapshots[path], updates[new_path] = original, changed
    end
  end
  assert(snapshots[source], "Source is not an Org file under the configured life directory")
  M.save(source)
  vim.fn.mkdir(vim.fn.fnamemodify(destination, ":h"), "p")
  local renamed, rename_err = os.rename(source, destination)
  assert(renamed, rename_err)
  local ok, err = pcall(function()
    for _, path in ipairs(vim.tbl_keys(updates)) do M.write(path, updates[path]) end
  end)
  if not ok then
    local restored, rollback_err = os.rename(destination, source)
    assert(restored, "Move rollback failed: " .. tostring(rollback_err))
    for path, lines in pairs(snapshots) do
      M.restore(path, lines)
    end
    error("Move rolled back: " .. tostring(err))
  end
  local buf = vim.fn.bufnr(source)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    vim.api.nvim_buf_set_name(buf, destination)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, updates[destination])
    vim.bo[buf].modified = false
    -- :file/set_name marks the path as not yet edited; re-read establishes its
    -- file state so the next ordinary :write does not raise E13.
    vim.api.nvim_buf_call(buf, function()
      local view = vim.fn.winsaveview()
      vim.cmd("silent keepalt edit")
      vim.fn.winrestview(view)
    end)
  end
  M.refresh()
  return destination
end

function M.active_lines(lines)
  local result, block = {}, nil
  for lnum, line in ipairs(lines) do
    local lower = line:lower()
    local kind = lower:match("^%s*#%+begin_(%w+)")
    if kind and ({ src = true, example = true, comment = true, export = true })[kind] then
      block = kind
    elseif block and lower:match("^%s*#%+end_" .. block .. "%s*$") then
      block = nil
    elseif not block and not line:match("^%s*#%s") then
      result[#result + 1] = { lnum = lnum, text = line }
    end
  end
  return result
end

-- Return the local destination and untouched Org search/line selector.
function M.local_target(source, target)
  local explicit = target:sub(1, 5) == "file:"
  local path = explicit and target:sub(6) or target
  if not explicit and (path:match("^[%w+.-]+:") or path:match("^[*#]")) then return nil end
  local selector = path:find("::", 1, true)
  local suffix = selector and path:sub(selector) or ""
  path = selector and path:sub(1, selector - 1) or path
  local base, line_number = path:match("^(.-)( %+%d+)$")
  if base then path, suffix = base, line_number .. suffix end
  if not explicit and not (path:match("^[./~]") or path:find("/", 1, true) or path:match("%.org[_%w]*$")) then
    return nil
  end
  if path == "" then return nil end
  path = vim.uri_decode(path)
  if path:sub(1, 1) == "~" then path = vim.fn.expand(path) end
  if path:sub(1, 1) ~= "/" then path = vim.fn.fnamemodify(source, ":h") .. "/" .. path end
  return vim.fs.normalize(path), suffix
end

function M.links(lines)
  local links = {}
  for _, line in ipairs(M.active_lines(lines)) do
    for target in line.text:gmatch("%[%[([^%]]+)%]") do
      links[#links + 1] = { target = target, lnum = line.lnum }
    end
  end
  return links
end

function M.quickfix(title, items)
  vim.fn.setqflist({}, " ", { title = title, items = items })
  if #items > 0 then vim.cmd("copen") else vim.notify(title .. ": no items") end
end

function M.command(name, fn, opts)
  vim.api.nvim_create_user_command(name, function(args)
    local ok, err = pcall(fn, args)
    if not ok then vim.notify(tostring(err), vim.log.levels.ERROR) end
  end, opts or {})
end

return M
