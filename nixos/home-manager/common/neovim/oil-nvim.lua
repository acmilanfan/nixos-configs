lua << EOF

require("oil").setup({
  keymaps = {
    ["<BS>"] = { "actions.parent", mode = "n" },
  },
})

EOF
