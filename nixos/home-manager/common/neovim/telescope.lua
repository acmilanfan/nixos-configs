lua << EOF

require('telescope').load_extension('orgmode')

-- for some reasons this does not work
--local builtin = require('telescope.builtin')
--vim.keymap.set('n', '<Leader>ff', ':Telescope find_files<CR>', {})
--vim.keymap.set('n', '<Leader>fg', builtin.live_grep, {})
--vim.keymap.set('n', '<Leader>fb', builtin.buffers, {})
--vim.keymap.set('n', '<Leader>fh', builtin.help_tags, {})

EOF
