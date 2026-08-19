require("glow").setup({})

vim.keymap.set("n", "<leader>mp", ":Glow<cr>", { silent = true, desc = "Preview markdown (glow)" })
