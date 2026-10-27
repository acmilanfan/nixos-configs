require("org-bullets").setup()
--require('headlines').setup()

local orgmode = require("orgmode")
local core = require("plugins.org.core")

local org_root = core.root()
local org_dir = org_root .. "/life"
local cwd = vim.fn.getcwd()
local agenda_files = {}

if core.within(cwd, org_root .. "/consume") then
  agenda_files = { ("%s/**/*.org"):format(cwd) }
elseif vim.fn.isdirectory(org_dir) == 1 then
  agenda_files = core.paths("execution")
else
  agenda_files = { ("%s/**/*.org"):format(cwd) }
end

local params = {
  org_agenda_files = agenda_files,
  org_default_notes_file = org_dir .. "/refile.org",
  org_tags_column = 0,
  org_hide_emphasis_markers = true,
  org_tags_exclude_from_inheritance = { "next_action" },
  org_agenda_skip_scheduled_if_done = true,
  org_agenda_skip_deadline_if_done = true,
  -- org_agenda_use_virtual_text = false,
  org_todo_keywords = { "TODO(t)", "DOING(p)", "HOLD(h)", "IDEA(i)", "NOTE(n)", "|", "DONE(d)", "SKIP(s)" },
  org_todo_keyword_faces = {
    DOING = ":foreground orange :slant italic :underline on :weight bold",
    HOLD = ":foreground grey :weight bold",
    SKIP = ":foreground purple :weight bold",
    IDEA = ":foreground green :slant italic",
    NOTE = ":foreground yellow :weight bold",
  },
  org_capture_templates = {
    t = {
      description = "Task",
      template = "* TODO %?\n  %u",
      target = org_dir .. "/tasks/tasks.org",
    },
    r = {
      description = "Refile / Quick Thought",
      template = "* TODO %?\n  %u",
      target = org_dir .. "/refile.org",
    },
    d = {
      description = "Brain Dump",
      template = "** %?\n   %u",
      target = org_dir .. "/dump.org",
    },
    i = {
      description = "Idea",
      template = "* IDEA %?\n  %u",
      target = org_dir .. "/notes/ideas/ideas.org",
      headline = "Ideas",
    },
    n = {
      description = "Note",
      template = "* NOTE %?\n  %u",
      target = org_dir .. "/refile.org",
    },
    j = {
      description = "Journal",
      template = "** %u day journal\n %?",
      target = org_dir .. "/journal/journal.org",
    },
  },
  org_agenda_custom_commands = {
    i = {
      description = "Tasks and ideas review",
      types = {
        {
          type = "tags_todo",
          org_agenda_todo_ignore_scheduled = "all",
          org_agenda_overriding_header = "All todos",
          match = "-recurring-idea-work-youtube-article/TODO",
        },
        {
          type = "tags_todo",
          org_agenda_todo_ignore_scheduled = "all",
          org_agenda_overriding_header = "All ideas",
          org_agenda_files = core.paths("ideas"),
          match = '+TODO="IDEA"',
        },
      },
    },
    s = {
      description = "Inbox & Refile sweep",
      types = {
        {
          type = "tags",
          org_agenda_overriding_header = "Unprocessed Inbox Items (Refile, Mobile & Dumps)",
          match = '+category="refile"|+category="1refile_mobile"|+category="dump"',
        },
      },
    },
    p = {
      description = "Current project actions",
      types = {
        {
          type = "tags_todo",
          org_agenda_overriding_header = "Immediate project actions (independent of this/next planning tags)",
          org_agenda_files = core.paths("current"),
          match = "+project+next_action",
        },
      },
    },
    b = {
      description = "Planning project review",
      types = { { type = "tags", match = "+project", org_agenda_files = core.paths("planning"),
        org_agenda_overriding_header = "Planning projects and reference (not daily commitments)" } },
    },
    w = {
      description = "Weekenduo planning buckets",
      types = {
        { type = "tags_todo", match = "+this-recurring", org_agenda_overriding_header = "This planning period" },
        { type = "tags_todo", match = "+next-recurring", org_agenda_overriding_header = "Next planning period" },
        { type = "tags_todo", match = "+recurring", org_agenda_overriding_header = "Recurring" },
      },
    },
    y = {
      description = "Youtube",
      types = {
        {
          type = "tags_todo",
          org_agenda_todo_ignore_scheduled = "all",
          org_agenda_overriding_header = "All videos",
          match = "+youtube+Duration<300",
          org_agenda_sorting_strategy = { "category-down" },
        },
      },
    },
  },
}

orgmode.setup(params)

-- ── Load Org Domain Modules ──────────────────────────────────────────
local calories = require("plugins.org.calories")
local youtube = require("plugins.org.youtube")
local projects = require("plugins.org.projects")
local ideas = require("plugins.org.ideas")
local health = require("plugins.org.health")
local notes = require("plugins.org.notes")
local preview = require("plugins.org.preview")

calories.setup()
youtube.setup()
projects.setup()
ideas.setup()
health.setup()
notes.setup()
preview.setup()

vim.api.nvim_create_autocmd("FileType", {
  pattern = "org",
  group = vim.api.nvim_create_augroup("orgmode_custom_settings", { clear = true }),
  callback = function()
    pcall(vim.cmd, "TableModeEnable")
    -- nowait: the global <leader>op{c,p,r} project maps would otherwise delay this one.
    vim.keymap.set("n", "<leader>op", "<cmd>OrgKnowledgeRefile<CR>",
      { buffer = 0, nowait = true, desc = "Refile to knowledge or project" })
    vim.keymap.set("n", "<leader>os", require("telescope").extensions.orgmode.search_headings, { buffer = 0, desc = "Search headings" })

    -- Buffer-local YouTube keymaps
    youtube.setup_buffer_keymaps()

    -- Buffer-local Org rendered preview toggle.
    preview.setup_buffer(vim.api.nvim_get_current_buf())

    -- Calorie tracker keymaps — only in calories.org
    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath:match("calories%.org$") or filepath:match("calories%.org/") then
      calories.setup_buffer_keymaps()
    end
  end,
})
