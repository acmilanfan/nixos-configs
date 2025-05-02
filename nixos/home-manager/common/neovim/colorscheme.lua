lua << EOF

require('nightfox').setup({
  options = {
    styles = {
      comments = "italic",
      keywords = "bold",
      types = "italic,bold",
    },
  },
  palettes = {
    nightfox = {
      bg1 = "#1a1b26",
    },
  },
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

require('onedark').setup {
    style = 'darker',

    toggle_style_list = {'dark', 'darker', 'warm', 'warmer' },

    code_style = {
      comments = 'italic',
      keywords = 'italic,bold',
      functions = 'bold',
    },
}
-- require('onedark').load()
-- vim.cmd("colorscheme dracula")
-- vim.cmd("colorscheme onedark")
-- vim.cmd("colorscheme kanagawa")
-- vim.cmd("colorscheme tokyonight-night")
vim.cmd("colorscheme nightfox")

EOF
