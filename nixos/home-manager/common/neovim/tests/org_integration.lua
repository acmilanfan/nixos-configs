-- Load repository configuration against installed plugins; all writes go to fixtures.
local config_dir = vim.fn.getcwd() .. "/nixos/home-manager/common/neovim"
vim.opt.termguicolors = true -- Match the normal Neovim configuration's GUI color faces.
vim.opt.runtimepath:prepend(config_dir)
for _, plugin in ipairs({ "orgmode", "org-bullets", "plenary.nvim", "telescope.nvim", "telescope-orgmode" }) do
  vim.cmd("packadd " .. plugin)
end
require("telescope").load_extension("orgmode")
local root = vim.fn.expand("~/ai/artifacts/nixos-configs/org-integration-") .. vim.fn.getpid()
vim.g.org_root = root
-- Fixtures are disposable; remove them on success and failure alike.
local ok, err = xpcall(function()
  local function fixture(relative, lines)
    local path = root .. "/life/" .. relative
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    assert(vim.fn.writefile(lines, path) == 0)
    return path
  end
  local ideas_path = fixture("notes/ideas/ideas.org", { "* Ideas :idea:" })
  fixture("tasks/tasks.org", { "* Tasks :task:" })
  fixture("refile.org", { "* Inbox" })
  local current = fixture("projects/current/active.org", {
    "#+TITLE: Active", "#+CATEGORY: Active", "#+FILETAGS: :project:", "* Active",
    "** Outcome", "- [ ] Deliver the result", "** TODO Deliver :this:next_action:",
  })
  fixture("projects/planning/later.org", { "* Later :project:", "** TODO Future :next:" })
  fixture("projects/finished/history.org", { "* Historical reference" })
  for name in pairs(package.loaded) do if name:match("^plugins%.org") then package.loaded[name] = nil end end
  require("plugins.orgmode")
  local orgmode, core = require("orgmode"), require("plugins.org.core")
  for _, command in ipairs({ "OrgCheck", "OrgProjectReview", "OrgIdeaReview", "OrgIdeaPromote", "OrgNoteNew", "OrgKnowledge" }) do
    assert(vim.fn.exists(":" .. command) == 2, "Missing command: " .. command)
  end
  local agenda_files = orgmode.files:filenames()
  assert(vim.tbl_contains(agenda_files, current))
  assert(not vim.tbl_contains(agenda_files, root .. "/life/projects/planning/later.org"))
  assert(not vim.tbl_contains(agenda_files, ideas_path))
  print("PASS execution agenda excludes planning, notes and history")

  orgmode.capture:open_template_by_shortcut("i") -- Its promise resolves on close, not on opening.
  assert(vim.wait(5000, function() return vim.b.org_capture == true end, 10), "Capture window did not open")
  vim.cmd("stopinsert")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "* IDEA Integration capture :next:" })
  orgmode.capture:refile()
  assert(vim.wait(5000, function()
    return table.concat(core.read(ideas_path), "\n"):find("Integration capture", 1, true) ~= nil
  end, 10), "Capture did not reach the ideas file")
  local ideas = require("plugins.org.ideas").collect()
  assert(#ideas == 1 and ideas[1].title == "Integration capture" and ideas[1].headline.level == 2)
  assert(vim.tbl_contains(ideas[1].tags, "next"))
  print("PASS idea capture lands under Ideas and keeps the next planning tag")

  local capture_target = fixture("notes/tech/captured-note.org", { "* Captured notes" })
  orgmode.capture:open_template_by_shortcut("n")
  assert(vim.wait(5000, function() return vim.b.org_capture == true end, 10))
  vim.cmd("stopinsert")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "* NOTE Captured knowledge", "Keep this captured body" })
  local capture_source = core.current_headline()
  require("plugins.org.notes").refile_to(capture_source, { filename = capture_target, lnum = 1, file_root = false })
  assert(table.concat(core.read(capture_target), "\n"):find("** NOTE Captured knowledge", 1, true))
  assert(table.concat(core.read(capture_target), "\n"):find("Keep this captured body", 1, true))
  assert(not vim.b.org_capture)
  print("PASS transactional knowledge refiling also finalizes capture buffers")

  vim.cmd("OrgProjectReview")
  assert(#vim.fn.getqflist() == 2, "Review must include current and planning projects")
  vim.cmd("cclose")
  vim.cmd("edit " .. vim.fn.fnameescape(current))
  vim.cmd("OrgProjectReviewed")
  assert(core.headlines(current)[1]:get_property("REVIEWED"))
  vim.cmd("OrgProjectPlan")
  assert(vim.api.nvim_buf_get_name(0) == root .. "/life/projects/planning/active.org")
  assert(not vim.tbl_contains(orgmode.files:filenames(), current))
  print("PASS commands record reviews and refresh the agenda after lifecycle moves")

  local note = require("plugins.org.notes").create("tech", "Integration note")
  vim.cmd("edit " .. vim.fn.fnameescape(note))
  local selected = { filename = root .. "/life/projects/finished/history.org", lnum = 1,
    title = "Historical reference", file_root = false }
  local pick = core.pick
  core.pick = function(_, _, callback) callback(selected) end -- Headless user selection only.
  require("plugins.org.notes").insert_link()
  core.pick = pick
  local custom_id = core.headlines(selected.filename)[1]:get_property("CUSTOM_ID")
  assert(custom_id)
  assert(table.concat(core.read(note), "\n"):find("[[file:../../projects/finished/history.org::#" .. custom_id .. "][Historical reference]]", 1, true))
  print("PASS knowledge links target non-agenda historical headings")

  local refile_source = fixture("notes/tech/refile-source.org", { "* Move this", "Keep its body" })
  vim.cmd("edit " .. vim.fn.fnameescape(refile_source))
  core.pick = function(_, entries, callback)
    for _, item in ipairs(entries) do
      if item.filename == root .. "/life/tasks/tasks.org" and item.file_root then callback(item) return end
    end
    error("Task destination missing")
  end
  require("plugins.org.notes").refile()
  core.pick = pick
  assert(table.concat(core.read(root .. "/life/tasks/tasks.org"), "\n"):find("Keep its body", 1, true))
  assert(not table.concat(core.read(refile_source), "\n"):find("Keep its body", 1, true))
  print("PASS knowledge refiling retains execution destinations and moves content")

  local function local_map(lhs)
    local map = vim.fn.maparg(lhs, "n", false, true)
    assert(map.buffer == 1 and map.nowait == 1, lhs .. " must be a buffer-local nowait map: " .. vim.inspect(map))
  end
  local headless = fixture("notes/tech/no-heading.org", { "Text before any heading" })
  vim.cmd("edit " .. vim.fn.fnameescape(headless))
  local_map("<leader>op")
  assert(vim.fn.maparg("<leader>opr", "n") ~= "" and vim.fn.maparg("<leader>onk", "n") ~= "")
  local notify, errors = vim.notify, {}
  vim.notify = function(msg, level) if level == vim.log.levels.ERROR then errors[#errors + 1] = msg end end
  vim.v.errmsg = ""
  vim.api.nvim_feedkeys(vim.keycode("<leader>op"), "mx", false) -- Mapping errors surface in v:errmsg, not here.
  vim.notify = notify
  assert(vim.v.errmsg == "", "Refile off a heading must not raise: " .. vim.v.errmsg)
  assert(#errors == 1 and errors[1]:find("Place the cursor in an Org heading", 1, true), vim.inspect(errors))
  vim.cmd("edit " .. vim.fn.fnameescape(fixture("calories.org", { "* Food Library" })))
  local_map("<leader>on")
  print("PASS buffer-local refile and calorie maps skip global prefix waits and report errors")

  local preview_path = fixture("notes/tech/preview.org", { "* Preview" })
  vim.cmd("edit " .. vim.fn.fnameescape(preview_path))
  local preview_map = vim.fn.maparg("<leader>ov", "n", false, true)
  assert(preview_map.buffer == 1, "preview toggle must be buffer-local: " .. vim.inspect(preview_map))
  assert(vim.fn.exists(":OrgPreview") == 2, "OrgPreview command must exist")
  print("PASS org preview is wired into org buffers")
end, debug.traceback)
vim.fn.delete(root, "rf")
assert(ok, err)
print("Integration checks passed")
