lua << EOF

require('nightfox').setup({
  options = {
    styles = {
      comments = "italic",
      keywords = "bold",
      types = "italic,bold",
    }
  }
})

require("dracula").setup({
  theme = 'dracula-soft',
  colors = {
    selection = "#44475A",
  },
  italic_comment = true,
})

require('kanagawa').setup({
  commentStyle = { italic = true },
  functionStyle = {},
  keywordStyle = { bold = true },
  statementStyle = { bold = true },
  typeStyle = { bold = true, italic = true },
  terminalColors = true,
  theme = "wave",
})

-- vim.cmd("colorscheme duskfox")
-- vim.cmd("colorscheme dracula")
-- vim.cmd("colorscheme dracula-soft")
vim.cmd("colorscheme nightfox")
-- vim.cmd("colorscheme kanagawa")

EOF
