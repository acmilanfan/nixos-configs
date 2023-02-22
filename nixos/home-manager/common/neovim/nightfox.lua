lua << EOF

require('nightfox').setup({
  options = {
    dim_inactive = true;
    styles = {
      comments = "italic",
      keywords = "bold",
      types = "italic,bold",
    }
  }
})

vim.cmd("colorscheme nordfox")

EOF
