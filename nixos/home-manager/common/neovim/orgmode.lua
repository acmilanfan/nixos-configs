lua << EOF

require('org-bullets').setup()
--require('headlines').setup()

require('orgmode').setup_ts_grammar()
require('orgmode').setup({
  org_agenda_files = { '~/org/*', '~/org/**/*' },
  org_default_notes_file = '~/org/refile.org',
})

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'org',
  group = vim.api.nvim_create_augroup('orgmode_telescope_nvim', { clear = true }),
  callback = function()
    vim.keymap.set('n', '<leader>tp', require('telescope').extensions.orgmode.refile_heading)
    vim.keymap.set('n', '<leader>ts', require('telescope').extensions.orgmode.search_headings)
  end,
})

require('legendary').setup({
  funcs = {
    {
      function()
        --doSomeStuff()
      -- todo add my agenda query functions
      end,
      description = 'Do some stuff with a Lua function!',
    },
    {
      itemgroup = 'orgmode queries',
    },
  },
})

EOF
