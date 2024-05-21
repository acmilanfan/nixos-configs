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

require('onedark').setup {
    style = 'darker',

    toggle_style_list = {'dark', 'darker', 'warm', 'warmer' },

    code_style = {
      comments = 'italic',
      keywords = 'italic,bold',
      functions = 'bold',
    },
}
require('onedark').load()

-- vim.cmd("colorscheme dracula")
-- vim.cmd("colorscheme nightfox")
-- vim.cmd("colorscheme kanagawa")
vim.cmd("colorscheme onedark")

EOF
