lua << EOF

require('org-bullets').setup()
--require('headlines').setup()

require('orgmode').setup_ts_grammar()
local org = require('orgmode').setup({
  org_agenda_files = { '~/org/*', '~/org/**/*' },
  org_default_notes_file = '~/org/refile.org',
  org_tags_column = 0,
  org_hide_emphasis_markers = true,
  org_todo_keywords = { 'TODO(t)', 'DOING(p)', 'HOLD(h)', 'IDEA(i)', 'NOTE(n)', '|', 'DONE(d)', 'SKIP(s)' },
  org_todo_keyword_faces = {
    DOING = ':foreground orange :slant italic :underline on :weight bold',
    HOLD = ':foreground grey :weight bold',
    SKIP = ':foreground purple :weight bold',
    IDEA = ':foreground green :slant italic',
    NOTE = ':foreground yellow :weight bold',
  },
  org_capture_templates = {
    t = { description = 'Task', template = '* TODO %?\n  %u' },
    i = { description = 'Idea', template = '* IDEA %?\n  %u' },
    n = { description = 'Note', template = '* NOTE %?\n  %u' },
    j = { description = 'Journal', template = '** %u day journal\n %?', target = '~/org/journal/journal.org' },
  }
})

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'org',
  group = vim.api.nvim_create_augroup('orgmode_telescope_nvim', { clear = true }),
  callback = function()
    vim.keymap.set('n', '<leader>tp', require('telescope').extensions.orgmode.refile_heading)
    vim.keymap.set('n', '<leader>ts', require('telescope').extensions.orgmode.search_headings)
    vim.keymap.set('n', '<leader>os',
        function()
          local parseDate = function(date)
            local Y, M, D, h, m, s = date:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
            if Y == nil then
              error("Wrong ISO date format: " .. date)
              return os.time()
            end
            return os.time({ year = Y, month = M, day = D, hour = h, min = m, sec = s })
          end

          local sort_todos = function(todos)
            if todos == nil then
              return {}
            end
            table.sort(todos, function(a, b)
              local a_published = a:get_property('Published')
              local a_created = a:get_property('Created')
              local b_published = b:get_property('Published')
              local b_created = b:get_property('Created')
              if a_published and b_published then
                return parseDate(a_published) < parseDate(b_published)
              else
                if a_created and b_created then
                  return parseDate(a_created) < parseDate(b_created)
                else
                  if a:get_priority_sort_value() ~= b:get_priority_sort_value() then
                    return a:get_priority_sort_value() > b:get_priority_sort_value()
                  end
                  return a.category < b.category
                end
              end
            end)
            return todos
          end

          local utils = require('orgmode.utils')
          local AgendaTodosView = require('orgmode.agenda.views.todos')
          AgendaTodosView.generate_view = function(items, content, filters, win_width)
            items = sort_todos(items)

            local offset = #content
            local longest_category = utils.reduce(items, function(acc, todo)
              return math.max(acc, vim.api.nvim_strwidth(todo:get_category()))
            end, 0)

            for i, headline in ipairs(items) do
              if filters:matches(headline) then
                table.insert(content, AgendaTodosView.generate_todo_item(headline, longest_category, i + offset, win_width))
              end
            end

            return { items = items, content = content }
          end

          org.agenda.filters:parse('+youtube', true)
          org.agenda:open_agenda_view(AgendaTodosView, 'todos', {})
        end
    )
  end,
})

EOF
