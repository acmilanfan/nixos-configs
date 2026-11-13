package.path = vim.fn.getcwd() .. "/nixos/home-manager/common/neovim/tests/?.lua;" .. package.path
local h = require("org_preview_helpers")
h.load()
local preview = require("plugins.org.preview")
local root = h.root("markdown-preview-ui")

h.test("opens a Markdown preview and closes with q", function()
  local path = h.fixture(root, "life/notes/doc.md", { "# Doc", "Body" })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.setup({})
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  h.eq(vim.bo[pbuf].filetype, "org-preview")
  assert(table.concat(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false), "\n"):find("Doc", 1, true))
  vim.api.nvim_feedkeys(vim.keycode("q"), "mx", false)
  h.eq(vim.api.nvim_get_current_buf(), src)
end)

h.test("toggles a Markdown checkbox and leaves a link on the same line clickable", function()
  local path = h.fixture(root, "life/notes/check.md", {
    "# Doc", "- [ ] see [Example](https://example.com)",
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
  assert(line)
  local opened
  local original = vim.ui.open
  vim.ui.open = function(url) opened = url end
  vim.api.nvim_win_set_cursor(0, { line, col })
  vim.api.nvim_feedkeys(vim.keycode("<CR>"), "mx", false)
  vim.ui.open = original
  h.eq(opened, "https://example.com")
  h.eq(vim.api.nvim_buf_get_lines(src, 1, 2, false)[1], "- [ ] see [Example](https://example.com)")

  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.api.nvim_feedkeys(vim.keycode("<CR>"), "mx", false)
  h.eq(vim.api.nvim_buf_get_lines(src, 1, 2, false)[1], "- [x] see [Example](https://example.com)")
  h.eq(vim.bo[src].modified, true)
end)

h.test("scrolls within the preview for a same-file anchor", function()
  local path = h.fixture(root, "life/notes/anchor.md", {
    "# Doc", "## Section", "[Go](#section)", "## Other",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local line
  for i, text in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
    if text:find("Go", 1, true) then line = i end
  end
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.api.nvim_feedkeys(vim.keycode("<CR>"), "mx", false)
  h.eq(vim.api.nvim_get_current_buf(), pbuf)
  assert(vim.api.nvim_buf_get_lines(pbuf, vim.fn.line(".") - 1, vim.fn.line("."), false)[1]:find("Section", 1, true))
end)

h.test("opens a cross-file anchor and Ctrl-o returns to the preview", function()
  -- The heading is later than line 1 so the assertion cannot pass on the
  -- fallback to the first line.
  local target = h.fixture(root, "life/notes/target.md", {
    "# Target", "Body", "", "## Later",
  })
  local path = h.fixture(root, "life/notes/cross.md", {
    "# Doc", "[Go](target.md#later)",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local line
  for i, text in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
    if text:find("Go", 1, true) then line = i end
  end
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.api.nvim_feedkeys(vim.keycode("<CR>"), "mx", false)
  h.eq(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"), "target.md")
  h.eq(vim.fn.line("."), 4)
  vim.api.nvim_feedkeys(vim.keycode("<C-o>"), "mx", false)
  h.eq(vim.api.nvim_get_current_buf(), pbuf)
end)

h.test("cross-file #foo lands on the H1 when frontmatter owns the title", function()
  h.fixture(root, "life/notes/titled-target.md", {
    "---", "title: Foo", "---", "# Foo", "Body",
  })
  local path = h.fixture(root, "life/notes/titled-cross.md", {
    "# Doc", "[Go](titled-target.md#foo)",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local line
  for i, text in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
    if text:find("Go", 1, true) then line = i end
  end
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.api.nvim_feedkeys(vim.keycode("<CR>"), "mx", false)
  h.eq(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"), "titled-target.md")
  h.eq(vim.fn.line("."), 4, "the anchor must resolve to the H1, not the YAML title")
  vim.api.nvim_feedkeys(vim.keycode("<C-o>"), "mx", false)
  h.eq(vim.api.nvim_get_current_buf(), pbuf)
end)

h.test("opens a titled link with the bare URL", function()
  local path = h.fixture(root, "life/notes/titled-link.md", {
    "# Doc", '[Example](https://example.com "Display title")',
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
  assert(line, "the titled link must render its label")
  local opened
  local original = vim.ui.open
  vim.ui.open = function(url) opened = url end
  vim.api.nvim_win_set_cursor(0, { line, col })
  vim.api.nvim_feedkeys(vim.keycode("<CR>"), "mx", false)
  vim.ui.open = original
  h.eq(opened, "https://example.com")
  preview.close(src)
end)

h.test("fits rendered lines inside the preview text width", function()
  if #vim.api.nvim_list_wins() > 1 then vim.cmd("only") end
  local path = h.fixture(root, "life/notes/width.md", {
    "# Width", "",
    "| Name | Description |", "|:-----|:------------|",
    "| a | one two three four five six seven eight nine ten eleven twelve |",
  })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  vim.cmd("vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(win, 60)
  h.eq(vim.api.nvim_win_get_width(win), 60)
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  h.eq(vim.wo.foldcolumn, "2")
  local text_width = vim.api.nvim_win_get_width(0) - 2
  local border
  for i, text in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
    local used = vim.fn.strdisplaywidth(text)
    assert(used <= text_width, ("line %d uses %d of %d columns: %q"):format(i, used, text_width, text))
    if text:find("┌", 1, true) then border = text end
  end
  assert(border, "the table border must be rendered")
  h.eq(vim.fn.strdisplaywidth(border), text_width)
  preview.close(src)
end)

h.test("jumps to the Markdown source with <leader>oj", function()
  local path = h.fixture(root, "life/notes/jump.md", { "# Doc", "## Section", "Body" })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local src = vim.api.nvim_get_current_buf()
  preview.open(src)
  local pbuf = vim.api.nvim_get_current_buf()
  local line
  for i, text in ipairs(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)) do
    -- Markdown headings keep their level indent, so match the rendered text.
    if text:find("Section", 1, true) then line = i end
  end
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.api.nvim_feedkeys(vim.keycode("<leader>oj"), "mx", false)
  h.eq(vim.api.nvim_get_current_buf(), src)
  h.eq(vim.fn.line("."), 2)
  assert(not vim.api.nvim_buf_is_valid(pbuf))
end)

h.finish()
