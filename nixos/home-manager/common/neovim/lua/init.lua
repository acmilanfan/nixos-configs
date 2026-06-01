-- Defensive patch for Treesitter API changes/bugs in Neovim (fix for "range" nil value)
if vim.treesitter.get_node_text then
  local old_get_node_text = vim.treesitter.get_node_text
  vim.treesitter.get_node_text = function(node, source, opts)
    if not node or (type(node) ~= "userdata" and type(node) ~= "table") then
      return ""
    end
    local ok, has_range = pcall(function()
      return type(node.range) == "function"
    end)
    if not ok or not has_range then
      return ""
    end
    return old_get_node_text(node, source, opts)
  end
end

if vim.treesitter.get_range then
  local old_get_range = vim.treesitter.get_range
  vim.treesitter.get_range = function(node, source, metadata)
    if not node or (type(node) ~= "userdata" and type(node) ~= "table") then
      return 0, 0, 0, 0
    end
    local ok, has_range = pcall(function()
      return type(node.range) == "function"
    end)
    if not ok or not has_range then
      return 0, 0, 0, 0
    end
    return old_get_range(node, source, metadata)
  end
end

-- Plugin configurations
require("plugins.colorscheme")
require("plugins.nvim-web-devicons")
require("plugins.treesitter")
require("plugins.refactoring")
require("plugins.telescope")
require("plugins.lualine")
require("plugins.orgmode")
require("plugins.cmp")
require("plugins.hop")
require("plugins.indent-blankline")
require("plugins.comment")
require("plugins.which-key")
require("plugins.noice")
require("plugins.inc-rename")
require("plugins.fidget")
require("plugins.gitsigns")
require("plugins.go")
require("plugins.todo-comments")
require("plugins.harpoon")
require("plugins.null-ls")
require("plugins.autopairs")
require("plugins.highlight-undo")
require("plugins.nvim-surround")
require("plugins.rest-nvim")
require("plugins.barbecue")
require("plugins.navbuddy")
require("plugins.actions-preview")
require("plugins.zen-mode")
require("plugins.cloak-nvim")
require("plugins.pqf")
require("plugins.snacks")
require("plugins.oil-nvim")
require("plugins.avante")
require("plugins.minuet-ai")

-- Main configuration (keymaps, options, LSP, etc.)
require("config")
