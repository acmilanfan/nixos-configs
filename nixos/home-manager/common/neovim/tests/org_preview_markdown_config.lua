package.path = vim.fn.getcwd() .. "/nixos/home-manager/common/neovim/tests/?.lua;" .. package.path
local h = require("org_preview_helpers")
h.load()
local root = h.root("markdown-config")

h.test("configures render-markdown with wrapped tables and maps the preview", function()
  local setup
  package.loaded["render-markdown"] = {
    setup = function(opts) setup = opts end,
  }
  package.loaded["plugins.render-markdown"] = nil
  require("plugins.render-markdown")
  h.eq(setup.pipe_table.wrap, true)
  local path = h.fixture(root, "life/notes/doc.md", { "# Doc", "Body" })
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local map = vim.fn.maparg("<leader>ov", "n", false, true)
  h.eq(map.buffer, 1)
end)

h.test("glow is gone from the config", function()
  assert(vim.fn.filereadable("nixos/home-manager/common/neovim/lua/plugins/glow.lua") == 0)
  local hits = vim.tbl_filter(function(line) return line ~= "" end,
    vim.fn.systemlist("rg -n glow nixos/home-manager/common/neovim.nix nixos/home-manager/common/neovim/lua/init.lua"))
  h.eq(hits, {})
end)

h.test(":Preview and :OrgPreview exist", function()
  require("plugins.org.preview").setup({})
  assert(vim.fn.exists(":Preview") == 2)
  assert(vim.fn.exists(":OrgPreview") == 2)
end)

h.finish()
