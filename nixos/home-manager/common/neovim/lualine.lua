lua << EOF

require('lualine').setup {
  options = {
    icons_enabled = true,
    component_separators = '|',
    section_separators = '',
    -- theme = 'dracula'
  },
  sections = { lualine_a = {'buffers'} }
}

EOF
