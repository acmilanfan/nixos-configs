lua << EOF

require("nvim-tree").setup()
vim.api.nvim_set_keymap("n", "<C-h>", ":NvimTreeToggle<cr>" ,{silent = true, noremap = true})

EOF
