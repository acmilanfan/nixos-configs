package.path = vim.fn.getcwd() .. "/nixos/home-manager/common/neovim/tests/?.lua;" .. package.path
local h = require("org_preview_helpers")
h.load()
local preview = require("plugins.org.preview")
local state = require("plugins.org.preview.state")
local root = h.root("org-preview-ui")
vim.g.org_root = root

h.test("open and close restore the source window and options", function()
  local path = h.fixture(root, "life/notes/preview.org", { "#+TITLE: Preview", "* Heading", "Body" })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  vim.wo.number = true
  vim.wo.foldcolumn = "0"
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  local before = vim.fn.winsaveview()
  preview.setup({})
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  h.eq(vim.bo[pbuf].filetype, "org-preview")
  h.eq(vim.bo[pbuf].buftype, "nofile")
  h.eq(vim.bo[pbuf].bufhidden, "hide")
  h.eq(vim.bo[pbuf].modifiable, false)
  h.eq(vim.bo[pbuf].readonly, true)
  h.eq(vim.wo.number, false)
  h.eq(vim.wo.foldcolumn, "2", "preview uses a two-column left margin")
  assert(#vim.api.nvim_buf_get_lines(pbuf, 0, -1, false) > 0)
  local state = require("plugins.org.preview.state").get(src)
  h.eq(state.lines[vim.fn.line(".")].source, 2, "preview opens at the source cursor line")
  preview.close(src)
  h.eq(vim.api.nvim_get_current_buf(), src)
  h.eq(vim.wo.number, true)
  h.eq(vim.wo.foldcolumn, "0")
  h.eq(vim.fn.winsaveview().lnum, before.lnum)
  assert(not vim.api.nvim_buf_is_valid(pbuf))
end)

h.test("a hidden preview is shown again instead of duplicated", function()
  local first_path = h.fixture(root, "life/notes/first.org", { "* First" })
  local second_path = h.fixture(root, "life/notes/second.org", { "* Second" })
  vim.cmd("edit " .. vim.fn.fnameescape(first_path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  vim.cmd("edit " .. vim.fn.fnameescape(second_path))
  preview.toggle(src)
  h.eq(vim.api.nvim_get_current_buf(), pbuf)
end)

h.test("opening a preview hides every other visible preview", function()
  local a_path = h.fixture(root, "life/notes/visible-a.org", { "* Alpha" })
  local b_path = h.fixture(root, "life/notes/visible-b.org", { "* Beta" })
  vim.cmd("edit " .. vim.fn.fnameescape(a_path))
  local a = vim.api.nvim_get_current_buf()
  local win_a = vim.api.nvim_get_current_win()
  preview.open(a)
  local a_preview = vim.api.nvim_get_current_buf()
  vim.cmd("vsplit " .. vim.fn.fnameescape(b_path))
  local b = vim.api.nvim_get_current_buf()
  local win_b = vim.api.nvim_get_current_win()
  preview.open(b)
  local b_preview = vim.api.nvim_get_current_buf()

  h.eq(vim.api.nvim_win_get_buf(win_a), a)
  h.eq(vim.api.nvim_win_get_buf(win_b), b_preview)
  assert(vim.api.nvim_buf_is_valid(a_preview), "the hidden preview must stay for the jumplist")
  local a_state = state.get(a)
  assert(a_state and a_state.preview == a_preview, "the hidden preview keeps its state")

  -- Re-showing A hides B instead of leaving two previews visible.
  vim.api.nvim_set_current_win(win_a)
  preview.open(a)
  h.eq(vim.api.nvim_win_get_buf(win_a), a_preview)
  h.eq(vim.api.nvim_win_get_buf(win_b), b)
  assert(vim.api.nvim_buf_is_valid(b_preview) and state.get(b), "B stays hidden with its state")
  preview.close(a)
  preview.close(b)
end)

h.test("wiping the source wipes the preview", function()
  local path = h.fixture(root, "life/notes/wipe.org", { "* Wipe" })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_delete(src, { force = true })
  assert(not vim.api.nvim_buf_is_valid(pbuf))
end)

h.test("close restores the saved view in the preview window only", function()
  local contents = { "#+TITLE: Two windows", "* Heading" }
  for i = 1, 60 do contents[#contents + 1] = "Body " .. i end
  local path = h.fixture(root, "life/notes/two-windows.org", contents)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  local first = vim.api.nvim_get_current_win()
  vim.cmd("split")
  local second = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(first)
  vim.api.nvim_win_set_cursor(first, { 2, 0 })
  local saved = vim.fn.winsaveview()
  preview.setup({})
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_call(first, function() vim.fn.winrestview({ lnum = 8, topline = 8 }) end)
  vim.api.nvim_set_current_win(second)
  vim.api.nvim_win_set_cursor(second, { 50, 0 })
  local untouched = vim.fn.winsaveview()
  preview.close(src)
  h.eq(vim.api.nvim_win_get_buf(first), src)
  local restored = vim.api.nvim_win_call(first, function() return vim.fn.winsaveview() end)
  h.eq(restored.lnum, saved.lnum)
  h.eq(restored.topline, saved.topline)
  h.eq(vim.api.nvim_get_current_win(), second)
  h.eq(vim.api.nvim_win_get_cursor(second), { 50, 0 })
  h.eq(vim.fn.winsaveview().lnum, untouched.lnum)
  h.eq(vim.fn.winsaveview().topline, untouched.topline)
  assert(not vim.api.nvim_buf_is_valid(pbuf))
end)

h.test("preview applies heading, inline, link, table and code highlights", function()
  local path = h.fixture(root, "life/notes/highlights.org", {
    "#+TITLE: Highlights", "* H1", "A *bold* line with =inline= and [[https://example.com][Example]].",
    "| A | B |", "|---+---|", "| 1 | 2 |", "#+BEGIN_SRC lua", "print('x')", "#+END_SRC",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local marks = vim.api.nvim_buf_get_extmarks(pbuf, require("plugins.org.preview.highlights").ns, 0, -1, { details = true })
  local groups, line_groups = {}, {}
  for _, mark in ipairs(marks) do
    local d = mark[4]
    if d.hl_group then groups[d.hl_group] = true end
    if d.line_hl_group then
      groups[d.line_hl_group] = true
      line_groups[d.line_hl_group] = true
    end
  end
  assert(groups.OrgPreviewHeading1, vim.inspect(groups))
  assert(groups.OrgPreviewBold, vim.inspect(groups))
  assert(groups.OrgPreviewLink, vim.inspect(groups))
  assert(groups.OrgPreviewTableBorder, vim.inspect(groups))
  assert(groups.OrgPreviewCode, vim.inspect(groups))
  assert(line_groups.OrgPreviewCodeBlock, vim.inspect(line_groups))
  assert(not line_groups.OrgPreviewCode, vim.inspect(line_groups))
  local code_block = vim.api.nvim_get_hl(0, { name = "OrgPreviewCodeBlock" })
  assert(code_block.bg ~= nil, vim.inspect(code_block))
end)

h.test("dims the fallback title, done keywords, tags, and level-1 rule", function()
  local path = h.fixture(root, "life/notes/dim.org", { "* DONE Finished :tag:", "Body" })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local highlights = require("plugins.org.preview.highlights")
  local groups, line_groups = {}, {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(
    pbuf, highlights.ns, 0, -1, { details = true }
  )) do
    local d = mark[4]
    if d.hl_group then groups[d.hl_group] = true end
    if d.line_hl_group then
      groups[d.line_hl_group] = true
      line_groups[d.line_hl_group] = true
    end
  end
  assert(line_groups.OrgPreviewFallbackTitle, vim.inspect(line_groups))
  assert(not line_groups.OrgPreviewTitle, "the filename fallback is not a real title: " .. vim.inspect(line_groups))
  assert(line_groups.OrgPreviewRule, vim.inspect(line_groups))
  assert(groups.OrgPreviewDone, vim.inspect(groups))
  assert(groups.OrgPreviewTag, vim.inspect(groups))
  h.eq(vim.api.nvim_get_hl(0, { name = "OrgPreviewFallbackTitle" }).link, "Comment")
  h.eq(vim.api.nvim_get_hl(0, { name = "OrgPreviewDone" }).link, "Comment")
  h.eq(vim.api.nvim_get_hl(0, { name = "OrgPreviewTag" }).link, "Comment")
  preview.close(src)
end)

h.test("refresh replaces stale highlight marks", function()
  local path = h.fixture(root, "life/notes/refresh-highlights.org", {
    "* TODO First", "A *bold* line.",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local highlights = require("plugins.org.preview.highlights")
  local function mark_groups()
    local groups = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(pbuf, highlights.ns, 0, -1, { details = true })) do
      local d = mark[4]
      if d.hl_group then groups[d.hl_group] = true end
      if d.line_hl_group then groups[d.line_hl_group] = true end
    end
    return groups
  end
  local before = mark_groups()
  assert(before.OrgPreviewTodo and before.OrgPreviewBold and before.OrgPreviewHeading1, vim.inspect(before))
  vim.api.nvim_buf_set_lines(src, 0, -1, false, { "Plain text only." })
  preview.refresh(require("plugins.org.preview.state").get(src))
  local after = mark_groups()
  assert(after.OrgPreviewFallbackTitle, vim.inspect(after))
  assert(not after.OrgPreviewTodo, vim.inspect(after))
  assert(not after.OrgPreviewBold, vim.inspect(after))
  assert(not after.OrgPreviewHeading1, vim.inspect(after))
end)

h.test("refresh keeps the cursor on the same source line", function()
  local path = h.fixture(root, "life/notes/refresh-cursor.org", {
    "* Cursor",
    "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty",
    "* Later",
    "Body",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local state = require("plugins.org.preview.state").get(src)
  local row
  for i, value in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
    if value == "Later" then row = i end
  end
  assert(row, vim.inspect(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)))
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  -- Reflow only the paragraph above: "Later" keeps source line 3 while its
  -- rendered row moves, so a preserved line index would land elsewhere.
  vim.api.nvim_buf_set_lines(src, 1, 2, false, {
    "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twenty-one twenty-two twenty-three twenty-four",
  })
  preview.refresh(state)
  local after = vim.api.nvim_win_get_cursor(0)[1]
  h.eq(vim.api.nvim_buf_get_lines(pbuf, after - 1, after, false)[1], "Later")
  h.eq(state.lines[after].source, 3)
end)

h.test("refresh preserves the topline and rendered column", function()
  local contents = { "* Head", "Intro paragraph." }
  for i = 1, 12 do contents[#contents + 1] = "Paragraph " .. i .. " text." end
  contents[#contents + 1] = ""
  contents[#contents + 1] = "TARGET LINE keeps its words"
  local path = h.fixture(root, "life/notes/refresh-view.org", contents)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local preview_state = state.get(src)
  local target
  for i, text in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
    if text == "TARGET LINE keeps its words" then target = i end
  end
  assert(target, vim.inspect(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)))
  vim.api.nvim_win_set_cursor(0, { target, 5 })
  vim.fn.winrestview({ lnum = target, col = 5, topline = target - 3 })
  local saved = vim.fn.winsaveview()
  assert(saved.topline > 1, "the viewport must be scrolled for this check")
  local source_line = preview_state.lines[target].source
  -- Grow the paragraph above: the target keeps its source line while its
  -- rendered row moves down, so the viewport and column must be restored.
  vim.api.nvim_buf_set_lines(src, 1, 2, false, {
    "Intro paragraph " .. string.rep("with more words ", 12) .. "and a tail.",
  })
  preview.refresh(preview_state)
  local view = vim.fn.winsaveview()
  h.eq(view.topline, saved.topline)
  h.eq(view.col, 5)
  h.eq(preview_state.lines[view.lnum].source, source_line)
  preview.close(src)
end)

h.test("refresh keeps the wrapped segment of a paragraph", function()
  local paragraph = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi "
    .. "omicron pi rho sigma tau upsilon phi chi psi omega one two three four five six "
    .. "seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen"
  local path = h.fixture(root, "life/notes/refresh-segment.org", {
    "* Head", paragraph, "* Later", "Body",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local preview_state = state.get(src)
  local function segments()
    local rows = {}
    for i, line in ipairs(preview_state.lines) do
      if line.source == 2 then rows[#rows + 1] = i end
    end
    return rows
  end
  local rows = segments()
  assert(#rows >= 2, "the paragraph must wrap: " .. vim.inspect(rows))
  vim.api.nvim_win_set_cursor(0, { rows[2], 3 })
  -- Grow the heading above: every rendered row below moves while the
  -- paragraph keeps its source line and its wrapping.
  vim.api.nvim_buf_set_lines(src, 0, 1, false, { "* Head " .. string.rep("word ", 40) })
  preview.refresh(preview_state)
  local after = segments()
  assert(#after >= 2, "the paragraph must still wrap: " .. vim.inspect(after))
  h.eq(vim.fn.line("."), after[2])
  h.eq(vim.fn.col(".") - 1, 3)
  preview.close(src)
end)

h.test("re-renders after the source is reloaded from disk", function()
  local path = h.fixture(root, "life/notes/reload-source.org", { "* Original" })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  vim.fn.writefile({ "* Reloaded" }, path)
  vim.api.nvim_buf_call(src, function() vim.cmd("edit!") end)
  assert(vim.wait(500, function()
    local text = table.concat(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false), "\n")
    return text:find("Reloaded", 1, true) ~= nil and text:find("Original", 1, true) == nil
  end))
end)

h.test("falls back to the file when the source buffer is unloaded", function()
  local path = h.fixture(root, "life/notes/unload.org", { "#+TITLE: Unloaded", "* Heading", "Body" })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local preview_state = state.get(src)
  vim.fn.writefile({ "#+TITLE: Unloaded", "* From disk", "Body" }, path)
  vim.cmd("bunload! " .. src)
  assert(not vim.api.nvim_buf_is_loaded(src), "the source must be unloaded for this check")
  preview.refresh(preview_state)
  local found
  for _, text in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
    if text == "From disk" then found = true end
  end
  assert(found, vim.inspect(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)))
  preview.close(src)
end)

vim.cmd("packadd orgmode")
-- The Org mappings proxied by the preview are buffer-local and installed by
-- ftplugin/org.lua; `filetype on` in the helper only enables detection.
vim.cmd("filetype plugin on")
require("orgmode").setup({
  org_agenda_files = { root .. "/**/*.org" },
  org_default_notes_file = root .. "/refile.org",
  org_todo_keywords = { "TODO", "|", "DONE" },
})

h.test("toggles checkboxes, updates cookies, and marks the source modified", function()
  local path = h.fixture(root, "life/notes/checks.org", {
    "* Tasks [0/3]", "- [ ] open", "- [X] done", "- [-] half",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local function find(text)
    for i, line in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
      if line == text then return i end
    end
  end
  vim.api.nvim_win_set_cursor(0, { find("☐ open"), 0 })
  vim.api.nvim_feedkeys(vim.keycode("<CR>"), "mx", false)
  h.eq(vim.api.nvim_buf_get_lines(src, 1, 2, false)[1], "- [X] open")
  h.eq(vim.bo[src].modified, true)
  -- orgmode recounts every box: "done" was already checked, so this is 2/3.
  assert(table.concat(vim.api.nvim_buf_get_lines(src, 0, 1, false), "\n"):find("[2/3]", 1, true))
  assert(find("☑ open"), vim.inspect(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)))
  vim.api.nvim_win_set_cursor(0, { find("◪ half"), 0 })
  vim.api.nvim_feedkeys(vim.keycode("<CR>"), "mx", false)
  h.eq(vim.api.nvim_buf_get_lines(src, 3, 4, false)[1], "- [X] half")
end)

h.test("preview leaves a space leader free", function()
  local leader = vim.g.mapleader
  vim.g.mapleader = " "
  local ok, err = pcall(function()
    local path = h.fixture(root, "life/notes/space-leader.org", { "* Tasks", "- [ ] one" })
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local src = vim.api.nvim_get_current_buf()
    -- The source's own <leader>ov/<leader>oj/<Space> maps (wired in Org
    -- buffers) must never replace the preview's native keys.
    vim.keymap.set("n", "<Leader>ov", function() end, { buffer = src, desc = "source toggle" })
    vim.keymap.set("n", "<Leader>oj", function() end, { buffer = src, desc = "source jump" })
    vim.keymap.set("n", "<Space>", function() end, { buffer = src, desc = "source space" })
    preview.open(src)
    local pbuf = vim.api.nvim_get_current_buf()
    local lhs, descs = {}, {}
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(pbuf, "n")) do
      lhs[map.lhs] = true
      descs[map.lhs] = map.desc
    end
    assert(lhs[" ov"], "space-leader <leader>ov must stay reachable: " .. vim.inspect(vim.tbl_keys(lhs)))
    assert(lhs[" oj"], "space-leader <leader>oj must stay reachable: " .. vim.inspect(vim.tbl_keys(lhs)))
    assert(not lhs[" "], "bare <Space> must stay the leader: " .. vim.inspect(vim.tbl_keys(lhs)))
    h.eq(descs[" ov"], "Toggle Org preview")
    h.eq(descs[" oj"], "Jump to Org source")
  end)
  vim.g.mapleader = leader
  assert(ok, err)
end)

h.test("opens file links in the current window and Ctrl-o returns to the preview", function()
  local target = h.fixture(root, "life/notes/target note.org", { "* Target", "Body" })
  local source = h.fixture(root, "life/notes/link.org", {
    "* Source", "[[file:./target note.org::*Target][Go]]",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(source))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local line
  for i, text in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
    if text:find("Go", 1, true) then line = i end
  end
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.api.nvim_feedkeys(vim.keycode("<CR>"), "mx", false)
  h.eq(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"), "target note.org")
  h.eq(vim.fn.line("."), 1)
  vim.api.nvim_feedkeys(vim.keycode("<C-o>"), "mx", false)
  h.eq(vim.api.nvim_get_current_buf(), pbuf)
  vim.api.nvim_feedkeys(vim.keycode("<C-i>"), "mx", false)
  h.eq(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"), "target note.org")
end)

h.test("a link on a checkbox line opens before toggling", function()
  local path = h.fixture(root, "life/notes/link-checkbox.org", {
    "* Links", "- [ ] see [[https://example.com][Example]]",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local line, col
  for i, text in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
    local start = text:find("Example", 1, true)
    if start then line, col = i, start - 1 end
  end
  assert(line, "rendered link line missing")

  local opened
  local original = vim.ui.open
  vim.ui.open = function(url) opened = url end
  vim.api.nvim_win_set_cursor(0, { line, col })
  vim.api.nvim_feedkeys(vim.keycode("<CR>"), "mx", false)
  vim.ui.open = original
  h.eq(opened, "https://example.com")
  h.eq(vim.api.nvim_buf_get_lines(src, 1, 2, false)[1], "- [ ] see [[https://example.com][Example]]")

  -- The checkbox symbol still toggles when the cursor is on it, not the link.
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.api.nvim_feedkeys(vim.keycode("<CR>"), "mx", false)
  h.eq(vim.api.nvim_buf_get_lines(src, 1, 2, false)[1], "- [X] see [[https://example.com][Example]]")
end)

h.test("opens https links through vim.ui.open", function()
  local source = h.fixture(root, "life/notes/url.org", { "* URL", "[[https://example.com][Example]]" })
  vim.cmd("edit " .. vim.fn.fnameescape(source))
  preview.open(vim.api.nvim_get_current_buf())
  local pbuf = vim.api.nvim_get_current_buf()
  local line
  for i, text in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
    if text:find("Example", 1, true) then line = i end
  end
  local opened
  local original = vim.ui.open
  vim.ui.open = function(url) opened = url end
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.api.nvim_feedkeys(vim.keycode("gx"), "mx", false)
  vim.ui.open = original
  h.eq(opened, "https://example.com")
end)

h.test("resolves line and heading selectors in file links", function()
  h.fixture(root, "life/notes/selectors.org", {
    "* First", "Body", "* TODO Second",
  })
  local source = h.fixture(root, "life/notes/selector-links.org", {
    "* Source", "", "[[file:./selectors.org::2][Two]]", "", "[[file:./selectors.org::*Second][Second]]",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(source))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local function open(text)
    for i, value in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
      local start = value:find(text, 1, true)
      if start then vim.api.nvim_win_set_cursor(0, { i, start - 1 }) end
    end
    vim.api.nvim_feedkeys(vim.keycode("<CR>"), "mx", false)
    local line = vim.fn.line(".")
    vim.api.nvim_feedkeys(vim.keycode("<C-o>"), "mx", false)
    h.eq(vim.api.nvim_get_current_buf(), pbuf)
    return line
  end
  h.eq(open("Two"), 2)
  h.eq(open("Second"), 3)
end)

h.test("returns to the preview after an id link opens another file", function()
  local target = h.fixture(root, "life/notes/id-jump-target.org", { "* Target", "Body" })
  local source = h.fixture(root, "life/notes/id-jump.org", { "* Source", "[[id:jump][Jump]]" })
  vim.cmd("edit " .. vim.fn.fnameescape(source))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local line, col
  for i, text in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
    local start = text:find("Jump", 1, true)
    if start then line, col = i, start - 1 end
  end
  vim.api.nvim_win_set_cursor(0, { line, col })
  local orgmode = require("orgmode")
  local original = orgmode.action
  orgmode.action = function()
    vim.cmd("edit " .. vim.fn.fnameescape(target))
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
  end
  vim.api.nvim_feedkeys(vim.keycode("<CR>"), "mx", false)
  orgmode.action = original
  h.eq(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"), "id-jump-target.org")
  h.eq(vim.fn.line("."), 2)
  vim.api.nvim_feedkeys(vim.keycode("<C-o>"), "mx", false)
  h.eq(vim.api.nvim_get_current_buf(), pbuf)
  vim.api.nvim_feedkeys(vim.keycode("<C-i>"), "mx", false)
  h.eq(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"), "id-jump-target.org")
  h.eq(vim.fn.line("."), 2)
end)

-- A reflowed line can start with words from an earlier source line while the
-- link came from a later one, so id links must be located in the paragraph.
h.test("finds an id link on a later line of a reflowed paragraph", function()
  local path = h.fixture(root, "life/notes/id-source.org", {
    "* Source", "First line of the paragraph.", "Second line with [[id:abc][Jump]] here.",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local line, col
  for i, text in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
    local start = text:find("Jump", 1, true)
    if start then line, col = i, start - 1 end
  end
  vim.api.nvim_win_set_cursor(0, { line, col })
  local orgmode = require("orgmode")
  local original = orgmode.action
  local called, cursor
  orgmode.action = function(action)
    called, cursor = action, { vim.fn.line("."), vim.fn.col(".") }
  end
  vim.api.nvim_feedkeys(vim.keycode("<CR>"), "mx", false)
  orgmode.action = original
  vim.api.nvim_win_set_buf(0, pbuf)
  h.eq(called, "org_mappings.open_at_point")
  h.eq(cursor, { 3, 18 })
end)

h.test("restores the source window options while a link replaces the preview", function()
  h.fixture(root, "life/notes/option-target.org", { "* Target", "Body" })
  local source = h.fixture(root, "life/notes/option-link.org", {
    "* Source", "[[file:./option-target.org][Go]]",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(source))
  local src = vim.api.nvim_get_current_buf()
  vim.wo.number = true
  vim.wo.conceallevel = 2
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  h.eq(vim.wo.number, false)
  h.eq(vim.wo.conceallevel, 0)
  local line
  for i, text in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
    if text == "Go" then line = i end
  end
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.api.nvim_feedkeys(vim.keycode("<CR>"), "mx", false)
  h.eq(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"), "option-target.org")
  h.eq(vim.wo.number, true)
  h.eq(vim.wo.conceallevel, 2)
  vim.api.nvim_feedkeys(vim.keycode("<C-o>"), "mx", false)
  h.eq(vim.api.nvim_get_current_buf(), pbuf)
  h.eq(vim.wo.number, false)
  h.eq(vim.wo.conceallevel, 0)
end)

h.test("resolves custom id selectors in file links", function()
  h.fixture(root, "life/notes/custom-id.org", {
    "* First", "Body", "* Second", ":PROPERTIES:", ":CUSTOM_ID: abc", ":END:", "More",
  })
  local source = h.fixture(root, "life/notes/custom-id-link.org", {
    "* Source", "",
    "[[file:./custom-id.org::#abc][Go]]", "",
    "[[file:./custom-id.org::#missing][Missing]]",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(source))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local function open(text)
    for i, value in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
      local start = value:find(text, 1, true)
      if start then vim.api.nvim_win_set_cursor(0, { i, start - 1 }) end
    end
    vim.api.nvim_feedkeys(vim.keycode("<CR>"), "mx", false)
    local line = vim.fn.line(".")
    vim.api.nvim_feedkeys(vim.keycode("<C-o>"), "mx", false)
    h.eq(vim.api.nvim_get_current_buf(), pbuf)
    return line
  end
  h.eq(open("Go"), 3)
  h.eq(open("Missing"), 1)
end)

h.test("jumps to the mapped source line and wipes the preview", function()
  local path = h.fixture(root, "life/notes/jump.org", {
    "#+TITLE: Jump", "* Heading", "| A | B |", "|---+---|", "| 1 | 2 |",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local line
  for i, text in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
    if text == "Heading" then line = i end
  end
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.api.nvim_feedkeys(vim.keycode("<leader>oj"), "mx", false)
  h.eq(vim.api.nvim_get_current_buf(), src)
  h.eq(vim.fn.line("."), 2)
  assert(not vim.api.nvim_buf_is_valid(pbuf))

  preview.open(src)
  local pbuf2 = vim.api.nvim_get_current_buf()
  local row
  for i, text in ipairs(vim.api.nvim_buf_get_lines(pbuf2, 0, -1, false)) do
    if text:find("│ 1 │", 1, true) then row = i end
  end
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  vim.api.nvim_feedkeys(vim.keycode("<leader>oj"), "mx", false)
  h.eq(vim.fn.line("."), 5)
end)

-- A reflowed line starts at the paragraph's first source line, but a link can
-- come from a later one; the jump must land on the link's own line and column.
h.test("jumps to a link's source line and column", function()
  local path = h.fixture(root, "life/notes/jump-link.org", {
    "* Source", "First line of the paragraph.",
    "Second line with [[https://example.com][Example]] here.",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local line, col
  for i, text in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
    local start = text:find("Example", 1, true)
    if start then line, col = i, start - 1 end
  end
  vim.api.nvim_win_set_cursor(0, { line, col })
  vim.api.nvim_feedkeys(vim.keycode("<leader>oj"), "mx", false)
  h.eq(vim.api.nvim_get_current_buf(), src)
  assert(not vim.api.nvim_buf_is_valid(pbuf))
  h.eq(vim.api.nvim_win_get_cursor(0), { 3, 17 })
end)

h.test("jumps to a checkbox without changing the source", function()
  local path = h.fixture(root, "life/notes/jump-checkbox.org", {
    "* Tasks", "- [ ] open", "  - [X] nested",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local line
  for i, text in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
    if text:find("☐ open", 1, true) then line = i end
  end
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.api.nvim_feedkeys(vim.keycode("<leader>oj"), "mx", false)
  h.eq(vim.api.nvim_get_current_buf(), src)
  assert(not vim.api.nvim_buf_is_valid(pbuf))
  h.eq(vim.api.nvim_win_get_cursor(0), { 2, 2 })
  h.eq(vim.bo[src].modified, false)
end)

h.test("jumps from a table border to the row that owns it", function()
  local path = h.fixture(root, "life/notes/jump-border.org", {
    "* Table", "| A | B |", "|---+---|", "| 1 | 2 |",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local line
  for i, text in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
    if text:find("┌", 1, true) then line = i end
  end
  vim.api.nvim_win_set_cursor(0, { line, 2 })
  vim.api.nvim_feedkeys(vim.keycode("<leader>oj"), "mx", false)
  h.eq(vim.api.nvim_get_current_buf(), src)
  h.eq(vim.fn.line("."), 2)
end)

assert(vim.wait(500, function() return vim.fn.maparg("<Leader>ot", "n") ~= "" end), "org mappings not loaded")

local function find_preview(pbuf, text)
  for i, line in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
    if line:find(text, 1, true) then return i end
  end
end

h.test("mirrors TODO mappings onto the preview", function()
  local path = h.fixture(root, "life/notes/proxy.org", { "* TODO First" })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  assert(vim.wait(500, function() return vim.fn.maparg("cit", "n") ~= "" end), "TODO map missing")
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local maps = vim.api.nvim_buf_get_keymap(pbuf, "n")
  local has_cit = false
  for _, m in ipairs(maps) do if m.lhs == "cit" then has_cit = true end end
  assert(has_cit, "TODO mapping was not mirrored")
  vim.api.nvim_win_set_cursor(0, { find_preview(pbuf, "TODO First"), 0 })
  vim.api.nvim_feedkeys(vim.keycode("cit"), "mx", false)
  h.eq(vim.api.nvim_buf_get_lines(src, 0, 1, false)[1], "* DONE First")
  assert(vim.wait(500, function()
    return table.concat(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false), "\n"):find("DONE First", 1, true) ~= nil
  end))
end)

h.test("a proxied action that leaves the source unchanged does not re-render", function()
  local path = h.fixture(root, "life/notes/no-change.org", { "* First", "Body" })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  vim.keymap.set("n", "<leader>oz", function() end, { buffer = src, desc = "preview no-op probe" })
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local previews = require("plugins.org.preview")
  local original = previews.refresh
  local preview_state = state.get(src)
  local calls = 0
  previews.refresh = function(target, ...)
    if target == preview_state then calls = calls + 1 end
    return original(target, ...)
  end
  local tick = vim.api.nvim_buf_get_changedtick(src)
  vim.api.nvim_win_set_cursor(0, { find_preview(pbuf, "First"), 0 })
  vim.api.nvim_feedkeys(vim.keycode("<leader>oz"), "mx", false)
  -- Let any scheduled refresh run; an unchanged source must not schedule one.
  vim.wait(80, function() return false end)
  previews.refresh = original
  h.eq(vim.api.nvim_buf_get_changedtick(src), tick)
  h.eq(calls, 0)
  preview.close(src)
end)

h.test("proxies <Leader><CR> meta-return to the source", function()
  local path = h.fixture(root, "life/notes/meta.org", { "* Heading" })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_set_cursor(0, { find_preview(pbuf, "Heading"), 0 })
  vim.api.nvim_feedkeys(vim.keycode("<Leader><CR>"), "mx", false)
  local lines = vim.api.nvim_buf_get_lines(src, 0, -1, false)
  h.eq(lines[#lines], "* ")
end)

h.test("proxies an async tags prompt to the source heading", function()
  local path = h.fixture(root, "life/notes/tags.org", { "* Heading" })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local Input = require("orgmode.ui.input")
  local original = Input.open
  Input.open = function() return require("orgmode.utils.promise").resolve(":proxied:") end
  vim.api.nvim_win_set_cursor(0, { find_preview(pbuf, "Heading"), 0 })
  vim.api.nvim_feedkeys(vim.keycode("<Leader>ot"), "mx", false)
  vim.wait(500, function()
    return vim.api.nvim_buf_get_lines(src, 0, 1, false)[1]:find(":proxied:", 1, true) ~= nil
  end)
  Input.open = original
  assert(vim.api.nvim_buf_get_lines(src, 0, 1, false)[1]:find(":proxied:", 1, true))
  assert(vim.wait(500, function()
    return table.concat(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false), "\n"):find(":proxied:", 1, true) ~= nil
  end))
end)

h.test("re-renders on source edits, resize, and when a hidden preview returns", function()
  local target = h.fixture(root, "life/notes/away.org", { "* Away" })
  local path = h.fixture(root, "life/notes/live.org", {
    "* Live", "| A | B |", "|---+---|", "| one two three four five six | seven eight nine ten |",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  -- Headless Neovim lays every window out in one full-width column, where a
  -- per-window width change is a no-op, and it never delivers resize events.
  -- Split first, then resize the preview window and announce it as a UI would.
  vim.cmd("vsplit")
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(src, -1, -1, false, { "New body" })
  assert(vim.wait(500, function()
    return table.concat(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false), "\n"):find("New body", 1, true) ~= nil
  end))
  local function border()
    for _, text in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
      if text:find("┌", 1, true) then return text end
    end
  end
  local width = vim.api.nvim_win_get_width(0)
  local before = border()
  vim.api.nvim_win_set_width(0, width - 20)
  vim.api.nvim_exec_autocmds("WinResized", {})
  assert(vim.wait(500, function() return border() ~= before end))
  vim.api.nvim_win_set_width(0, width)
  vim.cmd("edit " .. vim.fn.fnameescape(target))
  vim.api.nvim_buf_set_lines(src, -1, -1, false, { "While hidden" })
  -- Let the debounced refresh expire while the preview is hidden, so returning
  -- to it must render from the dirty flag rather than a pending timer.
  vim.wait(120, function() return false end)
  vim.api.nvim_feedkeys(vim.keycode("<C-o>"), "mx", false)
  assert(vim.wait(500, function()
    return table.concat(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false), "\n"):find("While hidden", 1, true) ~= nil
  end))
end)

h.test("bdeleting the preview clears state", function()
  local path = h.fixture(root, "life/notes/bdelete.org", { "* Remove me" })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  vim.cmd("bdelete! " .. pbuf)
  assert(not preview.is_preview(pbuf))
  preview.open(src)
  assert(vim.bo[vim.api.nvim_get_current_buf()].filetype == "org-preview")
end)

h.test(":OrgPreview closes the preview from the preview buffer", function()
  local path = h.fixture(root, "life/notes/command.org", { "* Command" })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.setup({})
  vim.cmd("OrgPreview")
  local pbuf = vim.api.nvim_get_current_buf()
  h.eq(vim.bo[pbuf].filetype, "org-preview")
  vim.cmd("OrgPreview")
  h.eq(vim.api.nvim_get_current_buf(), src)
  assert(not vim.api.nvim_buf_is_valid(pbuf), "closing from the preview must wipe it")

  -- Outside an Org buffer the command warns instead of raising.
  local scratch = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(scratch)
  local notify, level = vim.notify, nil
  vim.notify = function(_, l) level = l end
  local ok, err = pcall(vim.cmd, "OrgPreview")
  vim.notify = notify
  assert(ok, err)
  h.eq(level, vim.log.levels.WARN)
  vim.api.nvim_buf_delete(scratch, { force = true })
end)

h.test("the global <leader>ov warns outside Org buffers", function()
  preview.setup({})
  local scratch = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(scratch)
  local notify, messages = vim.notify, {}
  vim.notify = function(msg, level) messages[#messages + 1] = { msg = msg, level = level } end
  vim.api.nvim_feedkeys(vim.keycode("<leader>ov"), "mx", false)
  vim.notify = notify
  vim.api.nvim_buf_delete(scratch, { force = true })
  h.eq(#messages, 1)
  h.eq(messages[1].level, vim.log.levels.WARN)
  assert(messages[1].msg:find("Org", 1, true), messages[1].msg)
end)

-- Mapping-path coverage: these press the wired <leader>ov on real Org buffers.
-- setup_buffer(0) deliberately mirrors the FileType autocmd's old argument
-- shape, so a captured handle 0 would key every state under 0 instead of `src`.
h.test("the wired <leader>ov targets the current Org buffer, not handle 0", function()
  local a_path = h.fixture(root, "life/notes/wired-a.org", { "* Alpha" })
  local b_path = h.fixture(root, "life/notes/wired-b.org", { "* Beta" })
  vim.cmd("edit " .. vim.fn.fnameescape(a_path))
  local a = vim.api.nvim_get_current_buf()
  preview.setup_buffer(0)
  vim.api.nvim_feedkeys(vim.keycode("<leader>ov"), "mx", false)
  local a_preview = vim.api.nvim_get_current_buf()
  h.eq(vim.bo[a_preview].filetype, "org-preview")
  assert(find_preview(a_preview, "Alpha"), "A's map must render A")
  assert(state.get(a), "state must be keyed under A, not 0")
  h.eq(state.get(a).preview, a_preview)
  assert(state.get(0) == nil, "no state may be keyed under buffer 0")

  vim.cmd("edit " .. vim.fn.fnameescape(b_path))
  local b = vim.api.nvim_get_current_buf()
  preview.setup_buffer(0)
  vim.api.nvim_feedkeys(vim.keycode("<leader>ov"), "mx", false)
  local b_preview = vim.api.nvim_get_current_buf()
  h.eq(vim.bo[b_preview].filetype, "org-preview")
  assert(find_preview(b_preview, "Beta"),
    "B's map must render B: " .. vim.inspect(vim.api.nvim_buf_get_lines(b_preview, 0, -1, false)))
  assert(not find_preview(b_preview, "Alpha"), "B's map must not reuse A's preview")
  h.eq(state.get(b).preview, b_preview)
  assert(state.get(0) == nil, "no state may be keyed under buffer 0")
  preview.close(b)
  preview.close(a)
end)

h.test("closing a mapping-opened preview restores the source view and options", function()
  local path = h.fixture(root, "life/notes/wired-close.org", {
    "* Wired close", "one", "two", "three", "four",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  vim.wo.number = true
  vim.wo.conceallevel = 2
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  local view = vim.fn.winsaveview()
  preview.setup_buffer(0)
  vim.api.nvim_feedkeys(vim.keycode("<leader>ov"), "mx", false)
  h.eq(vim.bo[vim.api.nvim_get_current_buf()].filetype, "org-preview")
  h.eq(vim.wo.number, false)
  h.eq(vim.wo.conceallevel, 0)
  vim.api.nvim_feedkeys(vim.keycode("<leader>ov"), "mx", false)
  h.eq(vim.api.nvim_get_current_buf(), src)
  h.eq(vim.wo.number, true)
  h.eq(vim.wo.conceallevel, 2)
  h.eq(vim.fn.winsaveview().lnum, view.lnum)
  assert(state.get(src) == nil and state.get(0) == nil)
end)

h.test("a mapping-opened preview proxies checkbox actions to the source", function()
  local path = h.fixture(root, "life/notes/wired-check.org", {
    "* Tasks [0/2]", "- [ ] one", "- [ ] two",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.setup_buffer(0)
  vim.api.nvim_feedkeys(vim.keycode("<leader>ov"), "mx", false)
  local pbuf = vim.api.nvim_get_current_buf()
  local row = find_preview(pbuf, "☐ one")
  assert(row, vim.inspect(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)))
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  vim.api.nvim_feedkeys(vim.keycode("<CR>"), "mx", false)
  h.eq(vim.api.nvim_buf_get_lines(src, 1, 2, false)[1], "- [X] one")
  assert(table.concat(vim.api.nvim_buf_get_lines(src, 0, 1, false), "\n"):find("[1/2]", 1, true),
    "the source cookie must be recounted")
  h.eq(state.get(src).preview, pbuf)
  assert(state.get(0) == nil, "no state may be keyed under buffer 0")
  preview.close(src)
end)

h.test("mixing :OrgPreview and the mapping keeps one preview per source", function()
  local path = h.fixture(root, "life/notes/wired-mix.org", { "* Mixed" })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.setup_buffer(0)
  local function preview_count()
    local count = 0
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "org-preview" then count = count + 1 end
    end
    return count
  end
  vim.cmd("OrgPreview")
  local pbuf = vim.api.nvim_get_current_buf()
  h.eq(vim.bo[pbuf].filetype, "org-preview")
  local baseline = preview_count()
  h.eq(state.get(src).preview, pbuf)
  vim.cmd("edit " .. vim.fn.fnameescape(path)) -- hide the preview, source current again
  vim.api.nvim_feedkeys(vim.keycode("<leader>ov"), "mx", false)
  h.eq(vim.api.nvim_get_current_buf(), pbuf)
  h.eq(preview_count(), baseline)
  h.eq(state.get(src).preview, pbuf)
  assert(state.get(0) == nil, "no state may be keyed under buffer 0")
  vim.api.nvim_feedkeys(vim.keycode("<leader>ov"), "mx", false)
  h.eq(vim.api.nvim_get_current_buf(), src)
  assert(state.get(src) == nil and state.get(0) == nil)
  h.eq(preview_count(), baseline - 1)
end)

h.test("renders the largest org file within the ceiling", function()
  local path = vim.fn.expand("~/org/life/calories.org")
  if vim.fn.filereadable(path) == 0 then
    print("SKIP render ceiling: " .. path .. " is not readable")
    return
  end
  local lines = vim.fn.readfile(path)
  local start = vim.uv.hrtime()
  local out = require("plugins.org.preview.render").render(lines, { width = 120, filename = "calories.org" })
  local ms = (vim.uv.hrtime() - start) / 1e6
  print(("render calories.org: %.1f ms, %d lines"):format(ms, #out))
  assert(ms < 300, ("render took %.1f ms"):format(ms))
end)

-- Nothing else in this suite loads lua/config.lua, so load the real global
-- FileType autocmd here. Its missing org-preview parser fails inside pcall, so
-- a highlighter assertion cannot tell the skip apart from a silent failure;
-- spying on vim.treesitter.start can.
h.test("the global tree-sitter autocmd skips org-preview", function()
  for _, plugin in ipairs({ "telescope.nvim", "hop.nvim", "lsplinks", "cmp-nvim-lsp", "SchemaStore.nvim" }) do
    vim.cmd("packadd " .. plugin)
  end
  local dir = vim.fn.getcwd() .. "/nixos/home-manager/common/neovim"
  local loaded, load_err = pcall(dofile, dir .. "/lua/config.lua")
  assert(loaded, "config.lua failed to load: " .. tostring(load_err))
  local path = h.fixture(root, "life/notes/treesitter.org", { "* Parsed?" })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  local started, start = {}, vim.treesitter.start
  vim.treesitter.start = function(buf) started[buf] = true end
  local opened, open_err = pcall(preview.open, src)
  local pbuf = vim.api.nvim_get_current_buf()
  local control = vim.api.nvim_create_buf(true, false)
  vim.bo[control].filetype = "vim" -- No enabled language server matches this.
  vim.treesitter.start = start
  assert(opened, open_err)
  h.eq(vim.bo[pbuf].filetype, "org-preview")
  h.eq(vim.treesitter.highlighter.active[pbuf], nil)
  assert(not started[pbuf], "org-preview must be skipped: " .. vim.inspect(vim.tbl_keys(started)))
  assert(started[control], "the autocmd must still start tree-sitter for other filetypes")
  preview.close(src)
  vim.api.nvim_buf_delete(control, { force = true })
end)

h.finish()
