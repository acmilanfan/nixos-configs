require("glow").setup({
  border = "none",
  width_ratio = 1,
  height_ratio = 1,
  -- width/height act as a cap on the computed ratio size, not a target, so
  -- these must be set above any realistic terminal size or they'll shrink
  -- the window back down (glow.nvim's own default of 100 does exactly that).
  width = 9999,
  height = 9999,
})

vim.keymap.set("n", "<leader>mp", ":Glow<cr>", { silent = true, desc = "Preview markdown (glow)" })
