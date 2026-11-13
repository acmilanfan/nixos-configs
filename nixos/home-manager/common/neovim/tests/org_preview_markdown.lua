package.path = vim.fn.getcwd() .. "/nixos/home-manager/common/neovim/tests/?.lua;" .. package.path
local h = require("org_preview_helpers")
h.load()
local inline = require("plugins.org.preview.markdown_inline")

h.test("renders Markdown emphasis and code", function()
  local r = inline.render("**bold** and *italic* and `code` and ~~strike~~", { source_col = 0 })
  h.eq(r.text, "bold and italic and code and strike")
  h.eq(r.spans[1], { start_col = 0, end_col = 4, hl = "OrgPreviewBold" })
  h.eq(r.spans[2].hl, "OrgPreviewItalic")
  h.eq(r.spans[3].hl, "OrgPreviewCode")
  h.eq(r.spans[4].hl, "OrgPreviewStrike")
end)

h.test("accepts underscore emphasis and rejects intraword markers", function()
  local r = inline.render("__bold__ _italic_ snake_case")
  h.eq(r.text, "bold italic snake_case")
  h.eq(r.spans[1].hl, "OrgPreviewBold")
  h.eq(r.spans[2].hl, "OrgPreviewItalic")
  h.eq(#r.spans, 2)
end)

h.test("renders links, autolinks, bare URLs and images", function()
  local r = inline.render("see [Example](https://example.com) and <https://x.test> and https://bare.test/y", { source_col = 0 })
  h.eq(r.text, "see Example and https://x.test and https://bare.test/y")
  h.eq(r.links[1].target, "https://example.com")
  h.eq(r.links[1].source_col, 4)
  h.eq(r.links[2].target, "https://x.test")
  h.eq(r.links[3].target, "https://bare.test/y")
end)

h.test("renders images as labeled links", function()
  local r = inline.render("![Alt text](img.png)")
  h.eq(r.text, "image: Alt text")
  h.eq(r.links[1].target, "img.png")
end)

h.test("honors escapes and keeps byte offsets", function()
  local r = inline.render("\\*literal\\* é **bold**", { source_col = 0 })
  h.eq(r.text, "*literal* é bold")
  h.eq(r.spans[1].start_col, 13)
  h.eq(r.spans[1].end_col, 17)
end)

h.test("keeps balanced parentheses in destinations and bare URLs", function()
  local r = inline.render("[Foo](https://en.wikipedia.org/wiki/Foo_(bar))")
  h.eq(r.text, "Foo")
  h.eq(r.links[1].target, "https://en.wikipedia.org/wiki/Foo_(bar)")

  local bare = inline.render("see https://en.wikipedia.org/wiki/Foo_(bar) here")
  h.eq(bare.text, "see https://en.wikipedia.org/wiki/Foo_(bar) here")
  h.eq(bare.links[1].target, "https://en.wikipedia.org/wiki/Foo_(bar)")

  local prose = inline.render("(see https://x.test/a).")
  h.eq(prose.links[1].target, "https://x.test/a")
end)

h.test("strips inline link titles and keeps angle destinations", function()
  local double = inline.render('[doc](https://example.com "Title")')
  h.eq(double.text, "doc")
  h.eq(double.links[1].target, "https://example.com")

  local single = inline.render("[doc](https://example.com 'Title')")
  h.eq(single.text, "doc")
  h.eq(single.links[1].target, "https://example.com")

  local paren = inline.render("[doc](https://example.com (Title))")
  h.eq(paren.text, "doc")
  h.eq(paren.links[1].target, "https://example.com")

  local angle = inline.render('[doc](<https://example.com/a b> "Title")')
  h.eq(angle.text, "doc")
  h.eq(angle.links[1].target, "https://example.com/a b")

  local angle_plain = inline.render("[doc](<https://example.com>)")
  h.eq(angle_plain.links[1].target, "https://example.com")

  -- A title must not hide balanced parentheses that belong to the target.
  local balanced = inline.render('[doc](https://en.wikipedia.org/wiki/Foo_(bar) "Title")')
  h.eq(balanced.links[1].target, "https://en.wikipedia.org/wiki/Foo_(bar)")
end)

local markdown = require("plugins.org.preview.markdown")

local function find_line(lines, text)
  for _, line in ipairs(lines) do
    if line.text:find(text, 1, true) then return line end
  end
end

h.test("uses frontmatter title, then first H1, then filename", function()
  local fm = markdown.render({
    "---", "title: Front Matter", "---", "# Heading", "Body",
  }, { width = 60, filename = "doc.md" })
  h.eq(fm[1].text, "Front Matter")
  h.eq(fm[1].kind, "title")
  assert(find_line(fm, "Heading").kind == "heading")

  local h1 = markdown.render({ "# Consumed title", "Body" }, { width = 60, filename = "doc.md" })
  h.eq(h1[1].text, "Consumed title")
  h.eq(h1[1].kind, "title")
  assert(find_line(h1, "Body").kind == "paragraph")

  local fallback = markdown.render({ "Body" }, { width = 60, filename = "doc.md" })
  h.eq(fallback[1].text, "doc.md")
  h.eq(fallback[1].kind, "fallback-title")
  h.eq(markdown.slug("Hello, World!"), "hello-world")
end)

h.test("gives the H1 its slug when frontmatter already supplies the title", function()
  local out = markdown.render({
    "---", "title: Foo", "---", "# Foo", "Body",
  }, { width = 60, filename = "doc.md" })
  h.eq(out[1].text, "Foo")
  h.eq(out[1].kind, "title")
  h.eq(out[1].anchor, nil, "a frontmatter title must not reserve a heading slug")
  local h1
  for _, line in ipairs(out) do
    if line.kind == "heading" and line.source == 4 then h1 = line end
  end
  assert(h1, "the H1 must render in the body")
  h.eq(h1.text, "Foo")
  h.eq(h1.anchor, "foo")
end)

h.test("treats a leading --- pair without YAML as horizontal rules", function()
  local out = markdown.render({
    "---", "prose line", "---", "more prose",
  }, { width = 60, filename = "doc.md" })
  local text = table.concat(h.texts(out), "\n")
  assert(text:find("prose line", 1, true), "prose between the rules must stay visible")
  assert(text:find("more prose", 1, true))
  local rules = 0
  for _, line in ipairs(out) do if line.kind == "rule" then rules = rules + 1 end end
  h.eq(rules, 2)

  -- A key is not enough when the block also contains plain prose.
  local mixed = markdown.render({
    "---", "name: Example", "plain prose", "---", "Body",
  }, { width = 60, filename = "doc.md" })
  local mixed_text = table.concat(h.texts(mixed), "\n")
  assert(mixed_text:find("plain prose", 1, true))
  assert(mixed_text:find("name: Example", 1, true))
end)

h.test("hides YAML frontmatter without a title and still shows the H1", function()
  local out = markdown.render({
    "---", "name: Example", "description: A description", "---", "# Heading", "Body",
  }, { width = 60, filename = "doc.md" })
  h.eq(out[1].text, "Heading")
  h.eq(out[1].kind, "title")
  local text = table.concat(h.texts(out), "\n")
  assert(not text:find("name:", 1, true), text)
  assert(not text:find("description:", 1, true), text)
  assert(text:find("Body", 1, true))
end)

h.test("uses a frontmatter title and hides the rest of the block", function()
  local out = markdown.render({
    "---", "title: Doc", "description: hidden", "---", "Body",
  }, { width = 60, filename = "doc.md" })
  h.eq(out[1].text, "Doc")
  h.eq(out[1].kind, "title")
  local text = table.concat(h.texts(out), "\n")
  assert(not text:find("description:", 1, true), text)
  assert(text:find("Body", 1, true))
end)

h.test("renders headings, paragraphs, lists and task lists", function()
  local out = markdown.render({
    "## Section", "First line", "second line", "", "- one", "  - nested item with a long tail",
    "1. first", "- [ ] open task", "- [x] done", "- [-] half",
  }, { width = 20, filename = "doc.md" })
  h.eq(out[1].text, "doc.md")
  local section = assert(find_line(out, "Section"))
  h.eq(section.level, 2)
  h.eq(section.source, 1)
  assert(find_line(out, "First line"))
  assert(find_line(out, "• one"))
  assert(find_line(out, "  • nested item with"))
  assert(find_line(out, "    a long tail"))
  assert(find_line(out, "1. first"))
  local cb = assert(find_line(out, "☐ open task"))
  h.eq(cb.kind, "checkbox")
  h.eq(cb.checkbox.state, " ")
  h.eq(cb.checkbox.col, 2)
end)

h.test("renders fences, quotes, rules and frontmatter", function()
  local out = markdown.render({
    "---", "title: Doc", "---", "# Heading", "```lua", "print('x')", "```",
    "> quoted", "---",
  }, { width = 60, filename = "doc.md" })
  h.eq(out[1].text, "Doc")
  assert(find_line(out, "Heading").kind == "heading")
  assert(find_line(out, "  lua"))
  assert(find_line(out, "  print('x')"))
  local quoted = assert(find_line(out, "  quoted"))
  h.eq(quoted.spans[1].hl, "OrgPreviewItalic")
  local has_rule = false
  for _, line in ipairs(out) do if line.kind == "rule" then has_rule = true end end
  assert(has_rule)
end)

h.test("keeps fenced code inside an ordered list item", function()
  local out = markdown.render({
    "1. Run the command:", "   ```sh", "   echo hi", "   ```", "2. Next",
  }, { width = 60, filename = "doc.md" })
  local text = table.concat(h.texts(out), "\n")
  assert(text:find("1. Run the command:", 1, true))
  assert(text:find("  sh", 1, true))
  assert(text:find("  echo hi", 1, true))
  assert(text:find("2. Next", 1, true))
end)

h.test("wraps long headings with a hanging indent", function()
  local out = markdown.render({ "# one two three four five six seven eight nine ten" }, { width = 20 })
  assert(out[1].kind == "title")
  assert(out[1].text:find("one two", 1, true))
  assert(out[2].text:sub(1, 1) == " ")
end)

h.test("renders a Markdown table with alignment and wrapped cells", function()
  local out = markdown.render({
    "# Doc", "", "| Name | Count |", "|:-----|------:|", "| a | 2 |", "| b | 10 |",
  }, { width = 40, filename = "doc.md" })
  local text = table.concat(h.texts(out), "\n")
  assert(text:find("┌", 1, true))
  assert(text:find("Name", 1, true))
  assert(text:find("    10", 1, true))
  assert(out[#out].kind == "table")
end)

h.test("wraps a long Markdown table instead of collapsing a column", function()
  local out = markdown.render({
    "| Name | Description |", "|:-----|:------------|",
    "| a | one two three four five six seven eight nine ten eleven |",
  }, { width = 100, filename = "doc.md" })
  local border
  for _, line in ipairs(out) do
    if line.kind == "table" and line.border then border = line.text break end
  end
  assert(border)
  assert(vim.fn.strdisplaywidth(border) <= 100)
  local text = table.concat(h.texts(out), "\n")
  assert(text:find("Description", 1, true))
  assert(text:find("one two", 1, true))
  assert(text:find("eleven", 1, true))
end)

h.test("renders a Markdown table without outer pipes", function()
  local out = markdown.render({
    "Name | Count", ":--- | ---:", "a | 2",
  }, { width = 40, filename = "doc.md" })
  local text = table.concat(h.texts(out), "\n")
  assert(text:find("┌", 1, true))
  assert(text:find("Name", 1, true))
  assert(text:find("2", 1, true))
end)

h.test("keeps Org table rendering unchanged", function()
  local org_table = require("plugins.org.preview.table")
  local out = org_table.render({
    "| Name | Count |", "|------+-------|", "| a | 2 |",
  }, { width = 40, source_start = 1 })
  assert(out[1].text:find("┌", 1, true))
  assert(table.concat(h.texts(out), "\n"):find("Name", 1, true))
end)

h.test("renders the largest repo markdown doc within the ceiling", function()
  local path = vim.fn.getcwd() .. "/docs/vm-hyprland.md"
  if vim.fn.filereadable(path) == 0 then
    print("SKIP render ceiling: docs/vm-hyprland.md missing")
    return
  end
  local lines = vim.fn.readfile(path)
  local start = vim.uv.hrtime()
  local out = markdown.render(lines, { width = 120, filename = "vm-hyprland.md" })
  local ms = (vim.uv.hrtime() - start) / 1e6
  print(("render vm-hyprland.md: %.1f ms, %d lines"):format(ms, #out))
  assert(ms < 300)
end)

h.finish()
