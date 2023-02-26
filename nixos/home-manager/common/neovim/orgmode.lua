lua << EOF

require('org-bullets').setup()
--require('headlines').setup()

require('orgmode').setup_ts_grammar()
local org = require('orgmode').setup({
  org_agenda_files = { '~/org/*', '~/org/**/*' },
  org_default_notes_file = '~/org/refile.org',
  org_tags_column = 0,
  org_todo_keywords = { 'TODO(t)', 'DOING(p)', 'HOLD(h)', 'IDEA(i)', '|', 'DONE(d)', 'SKIP(s)' },
  org_todo_keyword_faces = {
    DOING = ':foreground orange :slant italic :underline on :weight bold',
    HOLD = ':foreground grey :weight bold',
    SKIP = ':foreground purple :weight bold',
    IDEA = ':foreground green :slant italic',
  }
})

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'org',
  group = vim.api.nvim_create_augroup('orgmode_telescope_nvim', { clear = true }),
  callback = function()
    vim.keymap.set('n', '<leader>tp', require('telescope').extensions.orgmode.refile_heading)
    vim.keymap.set('n', '<leader>ts', require('telescope').extensions.orgmode.search_headings)
    --vim.keymap.set('n', '<leader>cor', function()
    --  org.agenda:tags({ todo_only = true, search = 'recurring' })
    --end)
    --vim.keymap.set('n', '<leader>cor',
    --    function()
    --      local AgendaSearchView = require('orgmode.agenda.views.search')
    --      org.agenda:open_agenda_view(AgendaSearchView, 'search', { search = 'install' })
    --    end
    --)
    --vim.keymap.set('n', '<leader>cor',
    --    function() org.agenda:agenda({ org_agenda_start_day = '-3d', show_clock_report = true }) end
    --)
  end,
})

--require('legendary').setup({
--  keymaps = {
--    {
--      '<leader>con',
--      function() org.agenda:tags({ todo_only = true, search = '-recurring' }) end,
--      description = 'Not recurring TODO tasks',
--    },
--    {
--      itemgroup = 'orgmode queries',
--    },
--  },
--})

EOF
