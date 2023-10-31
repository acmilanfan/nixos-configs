lua << EOF

require('telescope').load_extension('orgmode')
require('telescope').load_extension('lazygit')
require('telescope').load_extension('harpoon')
pcall(require('telescope').load_extension, 'fzf')

EOF
