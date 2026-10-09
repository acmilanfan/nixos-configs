-- nvim-treesitter and -textobjects are the `main` rewrites: setup() no longer
-- takes incremental_selection/textobjects tables (they were silently ignored),
-- keymaps are plain vim.keymap.set calls into the textobjects modules.
-- Highlighting is started per buffer in config.lua (vim.treesitter.start).

require("nvim-treesitter-textobjects").setup({
  select = {
    lookahead = true, -- jump forward to the textobject, like targets.vim
  },
  move = {
    set_jumps = true, -- record moves in the jumplist
  },
})

local select = require("nvim-treesitter-textobjects.select")
local move = require("nvim-treesitter-textobjects.move")
local swap = require("nvim-treesitter-textobjects.swap")

for keys, capture in pairs({
  aa = "@parameter.outer",
  ia = "@parameter.inner",
  af = "@function.outer",
  ["if"] = "@function.inner",
  ac = "@class.outer",
  ic = "@class.inner",
}) do
  vim.keymap.set({ "x", "o" }, keys, function()
    select.select_textobject(capture, "textobjects")
  end, { desc = "TS select " .. capture })
end

for keys, spec in pairs({
  ["]m"] = { move.goto_next_start, "@function.outer" },
  ["]]"] = { move.goto_next_start, "@class.outer" },
  ["]M"] = { move.goto_next_end, "@function.outer" },
  ["]["] = { move.goto_next_end, "@class.outer" },
  ["[m"] = { move.goto_previous_start, "@function.outer" },
  ["[["] = { move.goto_previous_start, "@class.outer" },
  ["[M"] = { move.goto_previous_end, "@function.outer" },
  ["[]"] = { move.goto_previous_end, "@class.outer" },
}) do
  vim.keymap.set({ "n", "x", "o" }, keys, function()
    spec[1](spec[2], "textobjects")
  end, { desc = "TS move " .. spec[2] })
end

-- <leader>x(change), not the old <leader>a: avante owns <leader>a* (config.lua),
-- and a bare <leader>a map would make every avante key wait for timeoutlen.
vim.keymap.set("n", "<leader>xa", function()
  swap.swap_next("@parameter.inner")
end, { desc = "TS swap parameter with next" })
vim.keymap.set("n", "<leader>xA", function()
  swap.swap_previous("@parameter.inner")
end, { desc = "TS swap parameter with previous" })

-- Incremental selection: nvim 0.12's built-in node selection (visual an/in)
-- replaces nvim-treesitter's removed module. <leader>v starts at the node
-- under the cursor and grows it; <leader>m shrinks it back.
vim.keymap.set("n", "<leader>v", "van", { remap = true, desc = "TS select node" })
vim.keymap.set("x", "<leader>v", "an", { remap = true, desc = "TS grow selection" })
vim.keymap.set("x", "<leader>m", "in", { remap = true, desc = "TS shrink selection" })
