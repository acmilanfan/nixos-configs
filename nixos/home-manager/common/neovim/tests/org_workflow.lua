-- Run from nixos-configs: nvim --headless -u NONE -l nixos/home-manager/common/neovim/tests/org_workflow.lua
local lua_dir = vim.fn.getcwd() .. "/nixos/home-manager/common/neovim/lua"
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(lua_dir, ":h"))
package.path = lua_dir .. "/?.lua;" .. lua_dir .. "/?/init.lua;" .. package.path
vim.cmd("packadd orgmode")
local root = vim.fn.expand("~/ai/artifacts/nixos-configs/org-workflow-tests-") .. vim.fn.getpid()
vim.fn.mkdir(root, "p")
vim.g.org_root = root
require("orgmode").setup({
  org_agenda_files = { root .. "/life/tasks/*.org", root .. "/life/projects/current/*.org" },
  org_default_notes_file = root .. "/life/refile.org",
  org_todo_keywords = { "TODO", "DOING", "HOLD", "IDEA", "NOTE", "|", "DONE", "SKIP" },
})
local failures, passed = {}, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("PASS " .. name)
  else
    failures[#failures + 1] = name .. ": " .. tostring(err)
    print("FAIL " .. failures[#failures])
  end
end
local function fixture(relative, lines)
  local path = root .. "/" .. relative
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  assert(vim.fn.writefile(lines, path) == 0)
  return path
end
local function eq(actual, expected)
  assert(vim.deep_equal(actual, expected), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
end
local function workflow(name)
  local ok, module = pcall(require, "plugins.org." .. name)
  assert(ok, "workflow module " .. name .. " must be available")
  return module
end

test("idea review sees every heading depth, excluding source blocks and archives", function()
  fixture("life/notes/ideas/ideas.org", {
    "* Ideas :idea:", "** IDEA Nested :this:", "*** IDEA Deeper :next:recurring:",
    "* IDEA Captured", "#+begin_src org", "* IDEA Example only", "#+end_src",
    "* Archived :ARCHIVE:", "** IDEA Old", "* SKIP Dropped",
  })
  local items = workflow("ideas").collect()
  eq(vim.tbl_map(function(item) return item.title end, items), { "Nested", "Deeper", "Captured" })
  assert(vim.tbl_contains(items[2].tags, "next"))
  assert(vim.tbl_contains(items[2].tags, "recurring"))
end)

test("file links resolve relative paths, selectors and spaces without treating URLs as files", function()
  local core = workflow("core")
  local source = root .. "/life/projects/current/test.org"
  local path, suffix = core.local_target(source, "file:../../notes/tech/a note.org::*Section")
  eq(path, root .. "/life/notes/tech/a note.org")
  eq(suffix, "::*Section")
  eq(core.local_target(source, "https://example.com/a.org"), nil)
  eq(core.local_target(source, "id:abc"), nil)
end)

test("link diagnostics skip code examples and comments and retain precise line numbers", function()
  fixture("life/notes/tech/a note.org", { "* Section" })
  local path = fixture("life/projects/current/links.org", {
    "* Links", "[[file:../../notes/tech/a note.org::*Section][Valid]]",
    "[[../../notes/missing.org][Broken]]", "#+begin_src org",
    "[[./example.org]]", "#+end_src", "# [[./comment.org]]",
  })
  local diagnostics = workflow("health").check_links(path)
  eq(#diagnostics, 1)
  eq(diagnostics[1].lnum, 3)
end)

test("project review reports outcome, open counts and the immediate action", function()
  local path = fixture("life/projects/current/review.org", {
    "#+TITLE: Review fixture", "#+FILETAGS: :project:", "* Review fixture",
    ":PROPERTIES:", ":REVIEWED: [2026-01-02 Fri]", ":END:",
    "** Outcome", "- [ ] Ship the result", "** Tasks",
    "*** TODO Implement :next:next_action:", "*** HOLD Waiting", "*** DONE Old",
  })
  local item
  for _, entry in ipairs(workflow("projects").collect("current")) do
    if entry.filename == path then item = entry end
  end
  assert(item, "project must appear in review")
  eq(item.open_count, 2)
  eq(item.outcome, "Ship the result")
  eq(item.next_action, "Implement")
  eq(item.reviewed, "[2026-01-02 Fri]")
end)

test("selecting a next action preserves this, next and recurring planning tags", function()
  local path = fixture("life/projects/current/action.org", {
    "* Project", "** TODO First :this:next_action:", "** TODO Second :next:recurring:",
  })
  workflow("projects").set_next(path, 3)
  local lines = vim.fn.readfile(path)
  assert(lines[2]:find(":this:", 1, true))
  assert(not lines[2]:find("next_action", 1, true))
  assert(lines[3]:find(":next:recurring:next_action:", 1, true))
end)

test("closed project diagnostics include open tasks and checkboxes but ignore source examples", function()
  local path = fixture("life/projects/finished/incomplete.org", {
    "* Closed", "** TODO Follow-up", "- [ ] Unfinished check", "#+begin_src org",
    "- [ ] Example", "#+end_src",
  })
  local issues = workflow("health").check_project(path, "finished")
  eq(#issues, 2)
  eq(issues[1].lnum, 2)
  eq(issues[2].lnum, 3)
end)

test("moving a project preserves inbound links, selectors and outgoing relative destinations", function()
  local source = fixture("life/projects/planning/move.org", {
    "* Move", "[[file:../../notes/tech/a note.org::*Section][Reference]]",
    "[[file:./move.org::*Move][Self]]", "[[file:./sibling.org][Sibling]]",
  })
  fixture("life/projects/planning/sibling.org", { "* Sibling" })
  local ref = fixture("life/notes/tech/move-ref.org", { "* Ref", "[[file:../../projects/planning/move.org::*Move][Project]]" })
  local target = root .. "/life/projects/current/move.org"
  workflow("core").move_file(source, target)
  assert(not vim.uv.fs_stat(source))
  assert(vim.uv.fs_stat(target))
  eq(vim.fn.readfile(ref)[2], "[[file:../../projects/current/move.org::*Move][Project]]")
  eq(vim.fn.readfile(target)[4], "[[file:../planning/sibling.org][Sibling]]")
  eq(vim.fn.readfile(target)[3], "[[file:move.org::*Move][Self]]")
end)

test("dirty referencing buffers abort moves and keep unsaved text", function()
  local source = fixture("life/projects/planning/dirty.org", { "* Dirty" })
  local ref = fixture("life/notes/tech/dirty-ref.org", { "[[file:../../projects/planning/dirty.org]]" })
  local buf = vim.fn.bufadd(ref)
  vim.fn.bufload(buf)
  vim.api.nvim_buf_set_lines(buf, 1, 1, false, { "Unsaved user text" })
  local ok = pcall(workflow("core").move_file, source, root .. "/life/projects/current/dirty.org")
  eq(ok, false)
  assert(vim.uv.fs_stat(source))
  eq(vim.api.nvim_buf_get_lines(buf, 1, 2, false), { "Unsaved user text" })
  vim.api.nvim_buf_delete(buf, { force = true })
end)

test("failed source saves and existing destinations never rename or overwrite", function()
  local source = fixture("life/projects/planning/readonly.org", { "* Original" })
  local buf = vim.fn.bufadd(source)
  vim.fn.bufload(buf)
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "* Unsaved" })
  vim.bo[buf].readonly = true
  eq(pcall(workflow("core").move_file, source, root .. "/life/projects/current/readonly.org"), false)
  assert(vim.uv.fs_stat(source))
  eq(vim.api.nvim_buf_get_lines(buf, 0, 1, false), { "* Unsaved" })
  vim.api.nvim_buf_delete(buf, { force = true })
  local target = fixture("life/projects/current/collision.org", { "* Existing" })
  eq(pcall(workflow("core").move_file, source, target), false)
  eq(vim.fn.readfile(target), { "* Existing" })
end)

test("a later link-save failure rolls back the move and already-updated references", function()
  local source = fixture("life/projects/planning/rollback.org", { "* Rollback" })
  local ref = fixture("life/notes/tech/rollback-ref.org", { "[[file:../../projects/planning/rollback.org]]" })
  local target = root .. "/life/projects/current/rollback.org"
  local core = workflow("core")
  local original = core.write
  core.write = function(path, lines)
    if path == ref then error("simulated link-save failure") end
    return original(path, lines)
  end
  local ok = pcall(core.move_file, source, target)
  core.write = original
  eq(ok, false)
  eq(vim.fn.readfile(source), { "* Rollback" })
  eq(vim.fn.readfile(ref), { "[[file:../../projects/planning/rollback.org]]" })
  assert(not vim.uv.fs_stat(target))
end)

test("categorized note creation cannot overwrite files or escape its category", function()
  local notes = workflow("notes")
  local path = notes.create("tech", "A useful decision")
  eq(path, root .. "/life/notes/tech/a-useful-decision.org")
  local lines = vim.fn.readfile(path)
  assert(vim.tbl_contains(lines, "#+TITLE: A useful decision"))
  assert(vim.tbl_contains(lines, "* A useful decision"))
  assert(type(notes.create) == "function")
  eq(pcall(notes.create, "tech", "A useful decision"), false)
  eq(pcall(notes.create, "../projects", "Escape"), false)
  eq(pcall(notes.create, "tech", "../escape"), false)
  eq(vim.fn.readfile(path), lines)
end)

test("knowledge navigation includes notes and finished projects outside the agenda", function()
  fixture("life/notes/tech/knowledge.org", { "#+TITLE: Knowledge note", "* Explanation" })
  fixture("life/projects/finished/knowledge.org", { "* Historical decision" })
  local entries = workflow("notes").collect()
  local titles = vim.tbl_map(function(item) return item.title end, entries)
  assert(vim.tbl_contains(titles, "Explanation"))
  assert(vim.tbl_contains(titles, "Historical decision"))
end)

test("mixed idea review selects never-reviewed, oldest-reviewed and random items without duplicates", function()
  fixture("life/notes/ideas/ideas.org", {
    "* Ideas", "** IDEA Never", "** IDEA Old", ":PROPERTIES:", ":REVIEWED: [2023-01-01 Sun]", ":END:",
    "** IDEA Recent", ":PROPERTIES:", ":REVIEWED: [2026-10-01 Thu]", ":END:",
    "** IDEA Other", ":PROPERTIES:", ":REVIEWED: [2025-01-01 Wed]", ":END:",
  })
  local items = workflow("ideas").review_items(3)
  eq(#items, 3)
  eq(items[1].title, "Never")
  eq(items[2].title, "Old")
  assert(items[3].title ~= "Never" and items[3].title ~= "Old")
end)

test("task promotion preserves idea body, child headings, planning tags and provenance", function()
  local source = fixture("life/notes/ideas/promote.org", {
    "* Ideas", "** IDEA Build this :next:recurring:", ":PROPERTIES:", ":EFFORT: 1h", ":END:",
    "A useful explanation.", "[[file:../tech/a note.org][Reference]]", "*** Details", "Child body", "** IDEA Other",
  })
  fixture("life/tasks/tasks.org", { "* Tasks :task:" })
  local ideas = workflow("ideas")
  local target = ideas.promote(source, 2, "task")
  eq(target, root .. "/life/tasks/tasks.org")
  local content = table.concat(vim.fn.readfile(target), "\n")
  assert(content:find("* TODO Build this :next:recurring:", 1, true))
  assert(content:find("A useful explanation.", 1, true))
  assert(content:find("** Details", 1, true))
  assert(content:find("[[file:../notes/tech/a note.org][Reference]]", 1, true))
  assert(content:find(":EFFORT: 1h", 1, true))
  assert(content:find(":ORIGIN:", 1, true))
  assert(content:find(":SOURCE_ID:", 1, true))
  eq(#workflow("health").check_links(target), 0)
  eq(pcall(ideas.promote, source, 2, "task"), false)
  assert(not vim.tbl_contains(vim.tbl_map(function(item)return item.title end, ideas.collect()), "Build this"))
end)

test("project promotion creates planning work with the original body and planning buckets", function()
  local source = fixture("life/notes/ideas/promote-project.org", {
    "* IDEA Try a project :this:", "Keep this research.", "** Research", "Useful result.",
  })
  local path = workflow("ideas").promote(source, 1, "project", "try-a-project")
  eq(path, root .. "/life/projects/planning/try-a-project.org")
  local content = table.concat(vim.fn.readfile(path), "\n")
  assert(content:find("Keep this research.", 1, true))
  assert(content:find(":this:", 1, true))
  assert(content:find("Origin:", 1, true))
  assert(content:find("*** Research", 1, true))
  eq(#workflow("health").check_links(path), 0)
end)

test("promotion failure restores destination and leaves the source idea unpromoted", function()
  local source = fixture("life/notes/ideas/failure.org", { "* IDEA Keep me", "Original research" })
  local target = fixture("life/tasks/tasks.org", { "* Tasks", "Existing task text" })
  local core, ideas = workflow("core"), workflow("ideas")
  local write = core.write
  core.write = function(path, lines)
    if path == source then error("simulated source-save failure") end
    return write(path, lines)
  end
  local ok = pcall(ideas.promote, source, 1, "task")
  core.write = write
  eq(ok, false)
  eq(vim.fn.readfile(source), { "* IDEA Keep me", "Original research" })
  eq(vim.fn.readfile(target), { "* Tasks", "Existing task text" })
end)

test("promotion cannot append a task into its own source file", function()
  local source = fixture("life/tasks/tasks.org", { "* IDEA Already here", "Keep the body" })
  local original = vim.fn.readfile(source)
  eq(pcall(workflow("ideas").promote, source, 1, "task"), false)
  eq(vim.fn.readfile(source), original)
end)

test("project promotion preserves research properties and does not rewrite example headings", function()
  local source = fixture("life/notes/ideas/properties.org", {
    "* IDEA More research", ":PROPERTIES:", ":EFFORT: 2h", ":END:",
    "#+begin_src org", "* Example heading", "#+end_src", "** Research", ":PROPERTIES:", ":OWNER: me", ":END:",
  })
  local target = workflow("ideas").promote(source, 1, "project", "research-properties")
  local content = table.concat(vim.fn.readfile(target), "\n")
  assert(content:find(":EFFORT: 2h", 1, true))
  assert(content:find(":OWNER: me", 1, true))
  assert(content:find("\n* Example heading\n", 1, true))
end)

test("invalid idea counts are rejected rather than silently using the default", function()
  assert(type(workflow("ideas").random_items) == "function", "Random review must validate its count")
  eq(pcall(workflow("ideas").random_items, "bad"), false)
  eq(pcall(workflow("ideas").review_items, 0), false)
  assert(#workflow("ideas").random_items() <= 3)
end)

test("knowledge refiling retains task destinations and excludes the source subtree", function()
  local source = fixture("life/notes/tech/refile.org", { "* Source", "** Child", "* Sibling" })
  fixture("life/tasks/refile-target.org", { "* Tasks destination" })
  local h = require("orgmode.api").load(source):get_headline_on_line(1)
  local entries = workflow("notes").refile_entries(h)
  local titles = vim.tbl_map(function(item)return item.title end, entries)
  assert(vim.tbl_contains(titles, "Tasks destination"))
  assert(vim.tbl_contains(titles, "Sibling"))
  assert(not vim.tbl_contains(titles, "Source"))
  assert(not vim.tbl_contains(titles, "Child"))
end)

test("transactional refiling rejects readonly destinations without removing the source", function()
  local path = fixture("life/notes/tech/safe-refile.org", { "* Keep me", "Do not lose this body" })
  local target = fixture("life/tasks/readonly-refile.org", { "* Destination" })
  local buf = vim.fn.bufadd(target)
  vim.fn.bufload(buf)
  vim.bo[buf].readonly = true
  local notes = workflow("notes")
  assert(type(notes.refile_to) == "function", "Refiling must use a checked transaction")
  local h = require("orgmode.api").load(path):get_headline_on_line(1)
  eq(pcall(notes.refile_to, h, { filename = target, lnum = 1, file_root = true }), false)
  eq(vim.fn.readfile(path), { "* Keep me", "Do not lose this body" })
  eq(vim.fn.readfile(target), { "* Destination" })
  vim.api.nvim_buf_delete(buf, { force = true })
end)

test("transactional refiling rebases links and restores both files on a failed source save", function()
  local path = fixture("life/notes/tech/checked-refile.org", { "* Move me", "[[file:a note.org::*Section][Reference]]" })
  local target = fixture("life/tasks/checked-refile.org", { "* Destination" })
  local h = require("orgmode.api").load(path):get_headline_on_line(1)
  local notes, core = workflow("notes"), workflow("core")
  assert(type(notes.refile_to) == "function")
  local write = core.write
  core.write = function(file, lines)
    if file == path then error("simulated source failure") end
    return write(file, lines)
  end
  local ok = pcall(notes.refile_to, h, { filename = target, lnum = 1, file_root = true })
  core.write = write
  eq(ok, false)
  eq(vim.fn.readfile(path), { "* Move me", "[[file:a note.org::*Section][Reference]]" })
  eq(vim.fn.readfile(target), { "* Destination" })
  notes.refile_to(h, { filename = target, lnum = 1, file_root = true })
  assert(table.concat(vim.fn.readfile(target), "\n"):find("[[file:../notes/tech/a note.org::*Section][Reference]]", 1, true))
  eq(#workflow("health").check_links(target), 0)
end)

test("a moved loaded project supports ordinary writes and persists finish metadata", function()
  local source = fixture("life/projects/planning/save-after-move.org", { "* Project", "** DONE Complete" })
  vim.cmd("edit " .. vim.fn.fnameescape(source))
  local target = root .. "/life/projects/current/save-after-move.org"
  workflow("core").move_file(source, target)
  vim.api.nvim_buf_set_lines(0, -1, -1, false, { "Normal edit" })
  vim.cmd("write")
  eq(vim.fn.readfile(target)[3], "Normal edit")
  workflow("projects").move("finished")
  local final = root .. "/life/projects/finished/save-after-move.org"
  assert(require("orgmode.api").load(final).headlines[1]:get_property("COMPLETED"))
  assert(table.concat(vim.fn.readfile(final), "\n"):find(":COMPLETED:", 1, true))
end)

test("non-saving BufWriteCmd handlers cause moves to fail and roll back", function()
  local source = fixture("life/projects/planning/custom-write.org", { "* Project" })
  local ref = fixture("life/notes/tech/custom-write-ref.org", { "[[file:../../projects/planning/custom-write.org]]" })
  local buf = vim.fn.bufadd(ref)
  vim.fn.bufload(buf)
  local autocmd = vim.api.nvim_create_autocmd("BufWriteCmd", { buffer = buf, callback = function() end })
  local ok = pcall(workflow("core").move_file, source, root .. "/life/projects/current/custom-write.org")
  vim.api.nvim_del_autocmd(autocmd)
  eq(ok, false)
  assert(vim.uv.fs_stat(source))
  eq(vim.fn.readfile(ref), { "[[file:../../projects/planning/custom-write.org]]" })
  eq(vim.bo[buf].modified, false)
  vim.api.nvim_buf_delete(buf, { force = true })
end)

test("finish diagnostics recognize partial and numbered checkboxes and lowercase archives", function()
  local path = fixture("life/projects/current/checkboxes.org", {
    "* Project", "- [-] Partly complete", "1. [ ] Numbered open item",
    "** Old :archive:", "- [ ] Archived checklist", "** Notes", "- [X] Done",
  })
  local issues = workflow("health").unfinished(path)
  eq(vim.tbl_map(function(item)return item.lnum end, issues), { 2, 3 })
end)

test("promoted parent ideas exclude copied descendants from review and direct promotion", function()
  local path = fixture("life/notes/ideas/parent-promoted.org", { "* IDEA Parent", "** IDEA Child", "Child body" })
  local ideas = workflow("ideas")
  ideas.promote(path, 1, "task")
  local source = require("orgmode.api").load(path)
  local child
  for _, h in ipairs(source.headlines) do if h.title == "Child" then child = h end end
  assert(child)
  assert(not vim.tbl_contains(vim.tbl_map(function(item)return item.title end, ideas.collect()), "Child"))
  eq(pcall(ideas.promote, path, child.position.start_line, "task"), false)
end)

test("provenance handles linked titles through stable file-local selectors", function()
  local source = fixture("life/notes/ideas/linked-title.org", { "* IDEA Try [[https://example.com][Example]]" })
  local target = workflow("ideas").promote(source, 1, "task")
  local h = require("orgmode.api").load(source).headlines[1]
  local id = h:get_property("CUSTOM_ID")
  assert(id, "Source needs a stable file-local selector")
  local content = table.concat(vim.fn.readfile(target), "\n")
  assert(content:find("linked-title.org::#" .. id .. "][", 1, true))
  assert(not content:find("::*Try [[", 1, true))
  eq(#workflow("health").check_links(target), 0)
end)

test("file-local completed IDEA states never enter review or promotion", function()
  local path = fixture("life/notes/ideas/completed-idea.org", { "#+TODO: TODO WAIT | IDEA DONE", "* IDEA Closed idea" })
  eq(require("orgmode.api").load(path).headlines[1].todo_type, "DONE")
  local ideas = workflow("ideas")
  assert(not vim.tbl_contains(vim.tbl_map(function(item)return item.title end, ideas.collect()), "Closed idea"))
  eq(pcall(ideas.promote, path, 2, "task"), false)
end)

test("transactional refiling can move a subtree within its file without losing sibling content", function()
  local path = fixture("life/notes/tech/same-file-refile.org", { "* First", "** Move", "Body", "* Second", "Other body" })
  local source = require("orgmode.api").load(path):get_headline_on_line(2)
  workflow("notes").refile_to(source, { filename = path, lnum = 4, file_root = false })
  eq(vim.fn.readfile(path), { "* First", "* Second", "Other body", "", "** Move", "Body" })
end)

test("consume detection is a path-prefix test, not a substring match", function()
  local core = workflow("core")
  assert(core.within(root .. "/consume", root .. "/consume"))
  assert(core.within(root .. "/consume/youtube/", root .. "/consume"))
  assert(not core.within(root .. "/consumer-service", root .. "/consume"))
  assert(not core.within("/elsewhere/consume", root .. "/consume"))
end)

test("youtube items include every open keyword, strip tags and refresh after a write", function()
  local path = fixture("consume/youtube/youtube1.org", {
    "* Videos :video:youtube:", "** TODO First video :music:", ":PROPERTIES:", ":Duration: 100", ":END:",
    "** DOING Second video", "** HOLD Third video :a:b:", "** DONE Watched video", "*** TODO Nested note",
  })
  local youtube = workflow("youtube")
  youtube.setup_commands()
  local function titles()
    return vim.tbl_map(function(item) return item.headline.todo_value .. " " .. item.headline.title end, youtube.collect())
  end
  eq(titles(), { "TODO First video", "DOING Second video", "HOLD Third video" })
  eq(youtube.collect()[1].headline:get_property("Duration"), "100")
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  vim.api.nvim_buf_set_lines(0, 7, 8, false, { "** TODO Rewatch video :later:" })
  vim.cmd("write")
  eq(titles(), { "TODO First video", "DOING Second video", "HOLD Third video", "TODO Rewatch video" })
  vim.cmd("bwipeout!")
end)

-- Fixtures are disposable; remove them on success and failure alike.
vim.fn.delete(root, "rf")
if #failures > 0 then
  error(string.format("%d passed, %d failed\n%s", passed, #failures, table.concat(failures, "\n")))
end
print(string.format("%d workflow checks passed", passed))
