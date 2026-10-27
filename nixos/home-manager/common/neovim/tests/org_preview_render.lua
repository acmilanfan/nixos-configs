package.path = vim.fn.getcwd() .. "/nixos/home-manager/common/neovim/tests/?.lua;" .. package.path
local h = require("org_preview_helpers")
h.load()
local render = require("plugins.org.preview.render")

h.test("renders header, heading, planning, body and code; hides metadata", function()
  local out = render.render({
    "#+TITLE: Weekly rhythm",
    "#+AUTHOR: Andrei",
    "#+DATE: 2026-10-26",
    "#+FILETAGS: :life:",
    "* TODO Heading :tag:",
    "SCHEDULED: <2026-10-27 Tue>",
    ":PROPERTIES:",
    ":ID: abc",
    ":END:",
    "Body text",
    "# a comment",
    "#+BEGIN_SRC lua",
    "print('hi')",
    "#+END_SRC",
  }, { width = 80, filename = "weekly.org" })
  h.eq(h.texts(out), {
    "Weekly rhythm", "Andrei · 2026-10-26", "", "", "TODO Heading :tag:",
    string.rep("─", 80), "Scheduled 2026-10-27 Tue", "", "Body text", "", "  lua",
    "  print('hi')",
  })
  h.eq(out[1].kind, "title")
  h.eq(out[2].kind, "meta")
  h.eq(out[5].kind, "heading")
  h.eq(out[5].level, 1)
  h.eq(out[5].source, 5)
  h.eq(out[6].kind, "rule")
  h.eq(out[7].kind, "planning")
  h.eq(out[9].kind, "paragraph")
  h.eq(out[11].text, "  lua")
  h.eq(out[11].source, 12)
  h.eq(out[11].spans, { { start_col = 2, end_col = 5, hl = "OrgPreviewMetadata" } })
  h.eq(out[12].kind, "code")
  h.eq(out[12].source, 13)
end)

h.test("uses the filename when there is no title", function()
  local out = render.render({ "* Heading" }, { width = 40, filename = "weekly.org" })
  h.eq(out[1].text, "weekly.org")
  h.eq(out[1].kind, "fallback-title")
end)

h.test("keeps quote content indented and marked italic", function()
  local out = render.render({
    "#+BEGIN_QUOTE",
    "quoted text",
    "#+END_QUOTE",
  }, { width = 40 })
  h.eq(out[1].text, "  quoted text")
  h.eq(out[1].kind, "paragraph")
  h.eq(out[1].spans, { { start_col = 2, end_col = 13, hl = "OrgPreviewItalic" } })
end)

h.test("reflows paragraphs, honors hard breaks, and renders lists", function()
  local out = render.render({
    "First line",
    "second line with words",
    "",
    "Hard break\\\\",
    "after break",
    "- one",
    "  - nested item with a long tail",
    "1. first",
    "- [ ] open task",
  }, { width = 20 })
  h.eq(h.texts(out), {
    "First line second", "line with words", "", "Hard break", "after break", "",
    "• one", "  • nested item with", "    a long tail", "1. first", "☐ open task",
  })
  h.eq(out[7].source, 6)
  h.eq(out[11].kind, "checkbox")
  h.eq(out[11].checkbox.state, " ")
  h.eq(out[11].checkbox.col, 2)
end)

h.test("renders every checkbox state at its nesting level", function()
  local out = render.render({
    "- [X] done",
    "  - [-] half",
  }, { width = 40 })
  h.eq(h.texts(out), { "☑ done", "  ◪ half" })
  h.eq(out[1].checkbox, { col = 2, state = "X" })
  h.eq(out[2].checkbox, { col = 4, state = "-" })
end)

h.test("keeps ordered numbers and normalizes the marker", function()
  local out = render.render({ "3) third" }, { width = 40 })
  h.eq(out[1].text, "3. third")
  h.eq(out[1].kind, "list")
end)

h.test("maps each reflowed paragraph line to its first word", function()
  local out = render.render({ "alpha beta", "gamma delta", "epsilon" }, { width = 12 })
  h.eq(h.texts(out), { "alpha beta", "gamma delta", "epsilon" })
  h.eq(out[1].source, 1)
  h.eq(out[2].source, 2)
  h.eq(out[3].source, 3)
end)

h.test("breaks words wider than the render width", function()
  local out = render.render({ "abcdefghij" }, { width = 5 })
  h.eq(h.texts(out), { "abcde", "fghij" })
  h.eq(out[2].source, 1)
end)

h.test("separates a list from a following paragraph", function()
  local out = render.render({ "- one", "plain text" }, { width = 40 })
  h.eq(h.texts(out), { "• one", "", "plain text" })
  h.eq(out[3].kind, "paragraph")
end)

h.test("absorbs indented list continuations into their item", function()
  local out = render.render({
    "- first item line",
    "  continuation words here",
    "  - nested item",
    "    nested continuation",
    "- last item",
  }, { width = 30 })
  h.eq(h.texts(out), {
    "• first item line continuation",
    "  words here",
    "  • nested item nested",
    "    continuation",
    "• last item",
  })
  h.eq(out[1].source, 1)
  h.eq(out[2].source, 2)
  h.eq(out[4].source, 4)
  h.eq(out[4].kind, "list")
end)

h.test("attaches a parent continuation after a nested item to its parent", function()
  local out = render.render({
    "- parent",
    "  - child",
    "  parent tail",
    "left paragraph",
  }, { width = 40 })
  h.eq(h.texts(out), { "• parent parent tail", "  • child", "", "left paragraph" })
end)

h.test("renders combined planning keywords on separate lines", function()
  local out = render.render({
    "* Task",
    "SCHEDULED: <2026-10-27 Tue> DEADLINE: <2026-10-28 Wed>",
    "SCHEDULED: <2026-10-27 Tue> CLOSED: [2026-10-26 Mon 12:00]",
    "CLOSED: [2026-10-26 Mon 12:00]",
  }, { width = 80 })
  h.eq(h.texts(out), {
    "Task", string.rep("─", 80),
    "Scheduled 2026-10-27 Tue", "Deadline 2026-10-28 Wed", "Scheduled 2026-10-27 Tue",
  })
  h.eq(out[3].source, 2)
  h.eq(out[4].source, 2)
  h.eq(out[5].source, 3)
end)

h.test("renders empty checkboxes without a bullet", function()
  local out = render.render({
    "- [ ]",
    "- [X]",
    "- [-]",
  }, { width = 20 })
  h.eq(h.texts(out), { "☐", "☑", "◪" })
  h.eq(out[1].kind, "checkbox")
  h.eq(out[1].checkbox.state, " ")
  h.eq(out[2].kind, "checkbox")
  h.eq(out[2].checkbox.state, "X")
  h.eq(out[3].kind, "checkbox")
  h.eq(out[3].checkbox.state, "-")
end)

local inline = require("plugins.org.preview.inline")

h.test("strips emphasis markers and exposes spans", function()
  local r = inline.render("*bold* and /italic/ and =code=", { source_col = 0 })
  h.eq(r.text, "bold and italic and code")
  h.eq(r.spans[1], { start_col = 0, end_col = 4, hl = "OrgPreviewBold" })
  h.eq(r.spans[2].hl, "OrgPreviewItalic")
  h.eq(r.spans[3].hl, "OrgPreviewCode")
end)

h.test("renders links and timestamps and keeps byte offsets", function()
  local r = inline.render("é *bold* [[https://example.com][Example]] <2026-10-27 Tue>", { source_col = 0 })
  h.eq(r.text, "é bold Example 2026-10-27 Tue")
  h.eq(r.spans[1].start_col, 3)
  h.eq(r.links[1].target, "https://example.com")
  h.eq(r.links[1].source_col, 10)
  h.eq(r.spans[#r.spans].hl, "OrgPreviewTimestampActive")
end)

h.test("linkifies bare URLs without trailing punctuation", function()
  local r = inline.render("see https://example.com/x.")
  h.eq(r.links[1].target, "https://example.com/x")
  h.eq(r.text, "see https://example.com/x.")
end)

h.test("headings keep TODO and tags with spans and clickable links", function()
  local out = render.render({ "* TODO See [[https://x][X]] :tag:" }, { width = 80 })
  h.eq(out[1].text, "TODO See X :tag:")
  h.eq(out[1].links[1].target, "https://x")
  local groups = vim.tbl_map(function(s) return s.hl end, out[1].spans)
  assert(vim.tbl_contains(groups, "OrgPreviewTodo"))
  assert(vim.tbl_contains(groups, "OrgPreviewTag"))
end)

h.test("wraps long headings with a hanging indent and a level-1 rule", function()
  local out = render.render({ "* TODO A long heading with several words to wrap :tag:" }, { width = 20 })
  h.eq(h.texts(out), {
    "TODO A long heading",
    "     with several",
    "     words to wrap",
    "     :tag:",
    string.rep("─", 20),
  })
  h.eq(out[1].spans, { { start_col = 0, end_col = 4, hl = "OrgPreviewTodo" } })
  h.eq(out[2].source, 1)
  h.eq(out[2].level, 1)
  h.eq(out[4].spans, { { start_col = 5, end_col = 10, hl = "OrgPreviewTag" } })
  h.eq(out[5].kind, "rule")
  h.eq(out[5].source, 1)
end)

h.test("adds an extra blank line above a later level-1 heading only", function()
  local out = render.render({ "* First", "Body", "** Nested", "* Second" }, { width = 40 })
  h.eq(h.texts(out), {
    "First", string.rep("─", 40), "", "Body", "", "  Nested", "", "", "Second",
    string.rep("─", 40),
  })
end)

h.test("strips inactive timestamps and file prefixes with offsets", function()
  local r = inline.render("due [2026-10-27 Tue] [[file:notes.org][Notes]]", { source_col = 10 })
  h.eq(r.text, "due 2026-10-27 Tue Notes")
  h.eq(r.spans[1], { start_col = 4, end_col = 18, hl = "OrgPreviewTimestampInactive" })
  h.eq(r.links[1], {
    start_col = 19, end_col = 24, target = "file:notes.org", source_col = 31,
  })
end)

h.test("file links hide their selector in the display text", function()
  local r = inline.render("[[file:notes.org::*Heading][Notes]] [[file:notes.org::*Other]]")
  h.eq(r.text, "Notes notes.org")
  h.eq(r.links[1].target, "file:notes.org::*Heading")
  h.eq(r.links[2].target, "file:notes.org::*Other")
end)

h.test("does not treat emphasis markers inside words", function()
  local r = inline.render("snake_case and 3*4")
  h.eq(r.text, "snake_case and 3*4")
  h.eq(r.spans, {})
end)

h.test("carries multi-word emphasis across wrapped lines", function()
  local out = render.render({ "alpha *bold words* omega" }, { width = 10 })
  h.eq(h.texts(out), { "alpha bold", "words", "omega" })
  h.eq(out[1].spans, { { start_col = 6, end_col = 10, hl = "OrgPreviewBold" } })
  h.eq(out[2].spans, { { start_col = 0, end_col = 5, hl = "OrgPreviewBold" } })
  h.eq(out[3].spans, nil)
end)

h.test("does not emit zero-width quote spans", function()
  local out = render.render({
    "#+BEGIN_QUOTE",
    "",
    "text",
    "#+END_QUOTE",
  }, { width = 40 })
  h.eq(out[1].spans, nil)
  h.eq(out[2].spans, { { start_col = 2, end_col = 6, hl = "OrgPreviewItalic" } })
end)

local table_render = require("plugins.org.preview.table")

h.test("draws a grid with a header and numeric alignment", function()
  local out = table_render.render({
    "| Name | Count |", "|------+-------|", "| a    |     2 |", "| b    |    10 |",
  }, { width = 40, source_start = 10 })
  h.eq(h.texts(out), {
    "┌──────┬───────┐", "│ Name │ Count │", "├──────┼───────┤",
    "│ a    │     2 │", "├──────┼───────┤", "│ b    │    10 │", "└──────┴───────┘",
  })
  h.eq(out[2].kind, "table")
  h.eq(out[2].source, 10)
  h.eq(out[4].source, 12)
  h.eq(out[1].source, 10)
  h.eq(out[3].source, 10)
  h.eq(out[7].source, 13)
  h.eq(out[2].spans, {
    { start_col = 4, end_col = 8, hl = "OrgPreviewBold" },
    { start_col = 13, end_col = 18, hl = "OrgPreviewBold" },
  })
end)

h.test("wraps long cells into a multi-line row", function()
  local out = table_render.render({
    "| Word | Description |", "|------+-------------|",
    "| a | one two three four five six seven |",
  }, { width = 30, source_start = 1 })
  h.eq(h.texts(out), {
    "┌──────┬─────────────────────┐",
    "│ Word │ Description         │",
    "├──────┼─────────────────────┤",
    "│ a    │ one two three four  │",
    "│      │ five six seven      │",
    "└──────┴─────────────────────┘",
  })
  h.eq(out[4].source, 3)
  h.eq(out[5].source, 3)
  h.eq(out[#out].source, 3)
end)

h.test("uses the available width for a near-fit table", function()
  local out = table_render.render({
    "| Name | Description |", "|------+-------------|",
    "| a | " .. string.rep("word ", 17) .. "words |",
  }, { width = 100, source_start = 1 })
  -- Natural width is 94 with an available 93: shave the single overflow byte
  -- from the wide column instead of collapsing it to the 8-column minimum.
  h.eq(vim.fn.strdisplaywidth(out[1].text), 100)
  h.eq(out[2].text, "│ Name │ Description" .. string.rep(" ", 79) .. "│")
  h.eq(#out, 6)
  assert(out[4].text:find("│ word word", 1, true), out[4].text)
end)

h.test("aligns wide characters by display width", function()
  local out = table_render.render({
    "| A | B |", "|---+---|", "| 界 | x |",
  }, { width = 40, source_start = 1 })
  h.eq(vim.fn.strdisplaywidth(out[1].text), vim.fn.strdisplaywidth(out[4].text))
end)

h.test("draws a one-column table without a separator", function()
  local out = table_render.render({ "| Item |", "| one |", "| two |" }, { width = 40, source_start = 1 })
  h.eq(out[1].text, "┌──────┐")
  h.eq(out[2].text, "│ Item │")
  h.eq(#out, 7)
end)

h.test("overflows horizontally when minimum widths do not fit", function()
  local out = table_render.render({
    "| A | B | C |", "|---+---+---|", "| one | two | three |",
  }, { width = 10, source_start = 1 })
  assert(#out[1].text > 10)
end)

h.test("carries table spans and links at rendered and source columns", function()
  local out = table_render.render({
    "| Name | Link |", "|------+------|", "| *bold* | [[https://x][X]] |",
  }, { width = 40, source_start = 1 })
  h.eq(out[4].text, "│ bold │ X    │")
  h.eq(out[4].spans, { { start_col = 4, end_col = 8, hl = "OrgPreviewBold" } })
  h.eq(out[4].links, { { start_col = 13, end_col = 14, target = "https://x", source_col = 11 } })
end)

h.test("honors alignment cookies with narrow and wide cells", function()
  local out = table_render.render({
    "| Left | Center | Right |",
    "|------+--------+-------|",
    "| <l>  | <c>    | <r8>  |",
    "| a    | b      | c     |",
    "| abcdefgh | abcdefgh | abcdefghij |",
  }, { width = 80, source_start = 1 })
  h.eq(h.texts(out), {
    "┌──────────┬──────────┬──────────┐",
    "│ Left     │  Center  │    Right │",
    "├──────────┼──────────┼──────────┤",
    "│ a        │    b     │        c │",
    "├──────────┼──────────┼──────────┤",
    "│ abcdefgh │ abcdefgh │ abcdefgh │",
    "│          │          │       ij │",
    "└──────────┴──────────┴──────────┘",
  })
  h.eq(out[2].spans, {
    { start_col = 4, end_col = 8, hl = "OrgPreviewBold" },
    { start_col = 18, end_col = 24, hl = "OrgPreviewBold" },
    { start_col = 33, end_col = 38, hl = "OrgPreviewBold" },
  })
  h.eq(out[4].spans, nil)
end)

h.test("uses <10> as an exact width for narrow and wide cells", function()
  local out = table_render.render({
    "| Wide | Narrow |",
    "|------+--------|",
    "| <10> | <4> |",
    "| abc | longer text here |",
  }, { width = 60, source_start = 1 })
  h.eq(h.texts(out), {
    "┌────────────┬──────┐",
    "│ Wide       │ Narr │",
    "│            │ ow   │",
    "├────────────┼──────┤",
    "│ abc        │ long │",
    "│            │ er   │",
    "│            │ text │",
    "│            │ here │",
    "└────────────┴──────┘",
  })
  h.eq(out[2].spans, {
    { start_col = 4, end_col = 8, hl = "OrgPreviewBold" },
    { start_col = 19, end_col = 23, hl = "OrgPreviewBold" },
  })
  h.eq(out[3].spans, { { start_col = 19, end_col = 21, hl = "OrgPreviewBold" } })
end)

h.test("renders table blocks through the document renderer", function()
  local out = render.render({ "* T", "| A | B |", "|---+---|", "| 1 | 2 |" }, { width = 40 })
  h.eq(h.texts(out), {
    "T", string.rep("─", 40), "", "┌───┬───┐", "│ A │ B │", "├───┼───┤",
    "│ 1 │ 2 │", "└───┴───┘",
  })
  h.eq(out[4].source, 2)
  h.eq(out[7].source, 4)
  h.eq(out[7].kind, "table")
  h.eq(out[4].border, true)
  h.eq(out[5].border, false)
end)

h.test("reads TODO/DONE keyword types from the Org config", function()
  vim.cmd("packadd orgmode")
  require("orgmode").setup({
    org_agenda_files = {},
    org_todo_keywords = { "TODO", "NEXT", "|", "DONE", "SKIP" },
  })
  local out = render.render({ "* SKIP Finished", "* NEXT Active" }, { width = 80 })
  h.eq(h.texts(out), {
    "SKIP Finished", string.rep("─", 80), "", "", "NEXT Active", string.rep("─", 80),
  })
  -- SKIP sits after the DONE separator, so it renders dim like DONE.
  h.eq(out[1].spans[1], { start_col = 0, end_col = 4, hl = "OrgPreviewDone" })
  h.eq(out[5].spans[1], { start_col = 0, end_col = 4, hl = "OrgPreviewTodo" })
end)

h.finish()
