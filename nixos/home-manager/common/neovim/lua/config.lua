-- mapleader/maplocalleader are set at the top of init.lua, before plugin
-- requires; see the comment there for why.
-- vim.o.clipboard = "unnamedplus"
vim.o.breakindent = true
vim.o.undofile = true
vim.o.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.o.swapfile = false
vim.o.backup = false
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.hlsearch = false
vim.o.incsearch = true
vim.o.completeopt = "menu,preview,menuone,noselect"
vim.o.termguicolors = true
vim.o.smartindent = true
vim.o.expandtab = true
vim.o.tabstop = 4
vim.o.softtabstop = 4
vim.o.shiftwidth = 4
vim.o.conceallevel = 2
vim.o.scrolloff = 8
vim.o.updatetime = 200
vim.o.colorcolumn = "120"
vim.o.wrap = false
vim.wo.number = true
vim.wo.relativenumber = true
vim.wo.cursorline = true
vim.g.lf_map_keys = 0

-- [[ Highlight on yank ]]
-- See `:help vim.hl.on_yank()`
local highlight_group = vim.api.nvim_create_augroup("YankHighlight", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function()
    vim.hl.on_yank()
  end,
  group = highlight_group,
  pattern = "*",
})

local bufwritegroup = vim.api.nvim_create_augroup("BufWriteGroup", {})
vim.api.nvim_create_autocmd({ "BufWritePre" }, {
  group = bufwritegroup,
  pattern = "*",
  callback = function()
    if vim.bo.filetype == "markdown" then return end
    vim.cmd([[%s/\s\+$//e]])
  end,
})

local builtin = require("telescope.builtin")
vim.keymap.set("n", "<Leader>ff", builtin.find_files, {})
vim.keymap.set(
  "n",
  "<Leader>fa",
  ":Telescope find_files find_command=rg,--no-ignore,--hidden,--files,--glob,!**/.git/*,--glob,!**/node_modules/*<CR>",
  { silent = true }
)
vim.keymap.set("n", "<Leader>fg", builtin.live_grep, {})
vim.keymap.set("n", "<Leader>fb", builtin.buffers, {})
vim.keymap.set("n", "<Leader>fh", builtin.help_tags, {})
vim.keymap.set("n", "<Leader>fk", builtin.keymaps, {})
vim.keymap.set("n", "<Leader>fc", builtin.commands, {})
vim.keymap.set("n", "<leader>fw", builtin.grep_string, { desc = "[S]earch current [W]ord" })
vim.keymap.set("n", "<leader>fd", builtin.diagnostics, { desc = "[S]earch [D]iagnostics" })
vim.keymap.set("n", "<leader>fr", builtin.resume, { desc = "[S]earch [R]esume" })
vim.keymap.set("n", "<leader>?", builtin.oldfiles, { desc = "[?] Find recently opened files" })
vim.keymap.set("n", "<leader>gf", builtin.git_files, { desc = "Search [G]it [F]iles" })
vim.keymap.set("n", "<leader>gs", builtin.git_status, { desc = "Search [G]it [5]tatus" })
vim.keymap.set("n", "<leader>/", function()
  -- You can pass additional configuration to telescope to change theme, layout, etc.
  builtin.current_buffer_fuzzy_find(require("telescope.themes").get_dropdown({
    winblend = 10,
    previewer = false,
  }))
end, { desc = "[/] Fuzzily search in current buffer" })

-- f/F/t/T hop to a char on the current line. They read the char themselves
-- and record it with setcharsearch(), so the built-in ; and , repeat the last
-- one like a native f/t. hint_patterns with the escaped char is what
-- hint_char1 does internally.
local hop = require("hop")
local directions = require("hop.hint").HintDirection
local function hop_char(forward, till)
  return function()
    local ok, c = pcall(vim.fn.getcharstr)
    if not ok or c == "\27" or c == "" then
      return
    end
    vim.fn.setcharsearch({ char = c, forward = forward and 1 or 0, ["until"] = till and 1 or 0 })
    hop.hint_patterns({
      direction = forward and directions.AFTER_CURSOR or directions.BEFORE_CURSOR,
      current_line_only = true,
      hint_offset = till and (forward and -1 or 1) or nil,
    }, vim.fn.escape(c, "\\/.$^~[]"))
  end
end
vim.keymap.set("", "f", hop_char(true, false), { remap = true, desc = "Hop to char" })
vim.keymap.set("", "F", hop_char(false, false), { remap = true, desc = "Hop back to char" })
vim.keymap.set("", "t", hop_char(true, true), { remap = true, desc = "Hop till char" })
vim.keymap.set("", "T", hop_char(false, true), { remap = true, desc = "Hop back till char" })

vim.keymap.set("n", "<leader>cn", ":IncRename ")
vim.keymap.set("n", "<leader>cw", function()
  return ":IncRename " .. vim.fn.expand("<cword>")
end, { expr = true })

vim.keymap.set("n", "<Leader>sf", ":LfWorkingDirectory<cr>", { silent = true, noremap = true })
-- vim.keymap.set("n", "<Leader>si", ":NvimTreeFindFile<cr>", { silent = true, noremap = true })
vim.keymap.set("n", "<Leader>si", ":Lf<cr>", { silent = true, noremap = true })
vim.keymap.set("n", "<Leader>of", ":Oil<cr>", { silent = true, noremap = true })

-- Not under <leader>k: that is lprev, which a <leader>k* map would delay.
vim.keymap.set("n", "<Leader>nd", function()
  require("notify").dismiss()
end, { desc = "Dismiss notifications" })

vim.keymap.set("n", "<Leader>nw", ":set wrap!<cr>", { silent = true })
vim.keymap.set("n", "<Leader>se", ":setlocal spell spelllang=en<cr>", { silent = true })
vim.keymap.set("n", "<Leader>sr", ":setlocal spell spelllang=ru<cr>", { silent = true })
vim.keymap.set("n", "<Leader>sd", ":setlocal spell spelllang=de<cr>", { silent = true })
vim.keymap.set("n", "<Leader>sc", ":setlocal spell spelllang=<cr>", { silent = true })
vim.keymap.set("n", "<Leader>ss", require("telescope.builtin").spell_suggest, {})
vim.keymap.set("n", "<C-I>", "<C-I>", {})

vim.keymap.set("n", "<Leader>ha", function()
  require("harpoon"):list():add()
end)
vim.keymap.set("n", "<Leader>hl", function()
  require("harpoon").ui:toggle_quick_menu(require("harpoon"):list())
end)
vim.keymap.set("n", "<Leader>hb", function()
  require("harpoon"):list():prev()
end)
vim.keymap.set("n", "<Leader>hf", function()
  require("harpoon"):list():next()
end)

vim.keymap.set("n", "<leader>u", vim.cmd.UndotreeToggle)
vim.keymap.set("n", "<leader>lg", vim.cmd.LazyGit)
vim.keymap.set("n", "<leader>lh", vim.cmd.LazyGitFilter)
vim.keymap.set("n", "<leader>lf", vim.cmd.LazyGitFilterCurrentFile)

vim.keymap.set("n", "<leader>sn", vim.cmd.Navbuddy)

-- Diagnostic keymaps
-- Jump and show the diagnostic in a float, as goto_prev/goto_next (removed in 0.13) did.
local function diagnostic_jump(count)
  return function()
    vim.diagnostic.jump({
      count = count,
      on_jump = function(_, bufnr)
        vim.diagnostic.open_float({ bufnr = bufnr, scope = "cursor", focus = false })
      end,
    })
  end
end
vim.keymap.set("n", "[d", diagnostic_jump(-1), { desc = "Go to previous diagnostic message" })
vim.keymap.set("n", "]d", diagnostic_jump(1), { desc = "Go to next diagnostic message" })
vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, { desc = "Open floating diagnostic message" })
vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Open diagnostics list" })

vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { silent = true })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { silent = true })
vim.keymap.set("n", "J", "mzJ`z")
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")
vim.keymap.set("x", "<leader>p", [["_dP]])
vim.keymap.set({ "n", "v" }, "<leader>d", '"_d')
vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]])
-- Not under <leader>y: that is the "+y operator.
vim.keymap.set(
  "n",
  "<leader>cy",
  'gv"+y',
  { noremap = true, silent = true, desc = "Copy last selection to system clipboard" }
)
vim.keymap.set("n", "<leader>Y", [["+Y]])
vim.keymap.set({ "n", "v" }, "<leader>i", [["+p]])

vim.keymap.set("n", "<leader>j", "<cmd>lnext<CR>zz")
vim.keymap.set("n", "<leader>k", "<cmd>lprev<CR>zz")
vim.keymap.set("n", "<C-j>", "<cmd>cnext<CR>zz")
vim.keymap.set("n", "<C-k>", "<cmd>cprev<CR>zz")

vim.keymap.set("n", "<C-f>", "<cmd>silent !tmux neww tmux-sessionizer<CR>")
vim.keymap.set("n", "<C-w>t", function()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local sorters = require("telescope.sorters")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local handle = io.popen("git worktree list --porcelain 2>/dev/null")
  if not handle then return end
  local output = handle:read("*a")
  handle:close()

  local worktrees = {}
  for path in output:gmatch("worktree (%S+)") do
    table.insert(worktrees, path)
  end

  if #worktrees == 0 then
    vim.notify("No git worktrees found", vim.log.levels.WARN)
    return
  end

  pickers.new({}, {
    prompt_title = "Git Worktrees",
    finder = finders.new_table({ results = worktrees }),
    sorter = sorters.get_generic_fuzzy_sorter(),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        local sel = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if sel then
          vim.cmd("cd " .. vim.fn.fnameescape(sel[1]))
          vim.notify("cwd → " .. sel[1])
        end
      end)
      return true
    end,
  }):find()
end, { desc = "Switch git worktree (cd)" })

vim.keymap.set("n", "<leader>zf", ":tab split<CR>", { silent = true })
vim.keymap.set("n", "<leader>zk", ":tab close<CR>", { silent = true })

vim.keymap.set("n", "Q", "@qj")
vim.keymap.set("x", "Q", ":norm @q<CR>")
-- Not under <leader>h, the harpoon keys.
vim.keymap.set("n", "<leader>ce", "oif err != nil {<CR>}<Esc>Oreturn err<Esc>", { desc = "Go: insert if err != nil" })

-- vim.keymap.set("n", "<leader>st", function()
--   vim.cmd("normal! qq")
--   vim.cmd("normal! ^/\\n<CR>:noh<CR>2xa<CR>")
--   vim.cmd("normal! @qq@q")
-- end, { remap = true })
--
-- vim.keymap.set("n", "<leader>mc", "qqhlq", { silent = true, remap = true })

vim.keymap.set("n", "<leader>nl", function()
  require("noice").cmd("last")
end)

vim.keymap.set("n", "<leader>nh", function()
  require("noice").cmd("history")
end)

vim.keymap.set("n", "<leader>ftt", function()
  require("FTerm").toggle()
end)

vim.keymap.set("n", "<leader>ftk", function()
  require("FTerm").close()
end)

vim.keymap.set("n", "<leader>ftm", function()
  require("FTerm").scratch({ cmd = "mvn clean compile" })
end)

vim.keymap.set("n", "<leader>ftp", function()
  require("FTerm").scratch({ cmd = "mvn clean package" })
end)

vim.keymap.set({ "n", "x" }, "<leader>rr", function()
  require("telescope").extensions.refactoring.refactors()
end)

vim.keymap.set("x", "<leader>nv", function()
  require("refactoring").refactor("Extract Variable")
end)

vim.keymap.set("x", "<leader>nm", function()
  require("refactoring").refactor("Extract Function")
end)

vim.keymap.set("n", "<leader>nb", function()
  require("refactoring").refactor("Extract Block")
end)

-- vim.keymap.set("n", "<leader>mm", require("onedark").toggle, { noremap = true, silent = true })
vim.keymap.set("n", "<leader>st", require("telescope.builtin").filetypes, { noremap = true, silent = true })

vim.keymap.set("n", "<leader>sls", ":set lines=10<CR>", { silent = true })
vim.keymap.set("n", "<leader>slm", ":set lines=20<CR>", { silent = true })
vim.keymap.set("n", "<leader>sll", ":set lines=30<CR>", { silent = true })
vim.keymap.set("n", "<leader>slr", ":set lines=999<CR>", { silent = true })
vim.keymap.set("n", "<leader>slw", "50<C-w>>", { silent = true })

local lsplinks = require("lsplinks")
lsplinks.setup()
vim.keymap.set("n", "gx", lsplinks.gx)

-- vim.keymap.set("n", "c-/", function() require("snacks").terminal() end, { desc = "Toggle Terminal" })
vim.keymap.set({ "n", "v" }, "<leader>gB", function()
  require("snacks").gitbrowse()
end, { desc = "Git Browse" })
vim.keymap.set("n", "<leader>bd", function()
  require("snacks").bufdelete()
end, { desc = "Delete Buffer" })
vim.keymap.set("n", "<leader>.", function()
  require("snacks").scratch()
end, { desc = "Toggle Scratch Buffer" })
vim.keymap.set("n", "<leader>S", function()
  require("snacks").scratch.select()
end, { desc = "Select Scratch Buffer" })

vim.keymap.set("v", "<", "<gv", { desc = "Indent out and keeps the selection" })
vim.keymap.set("v", ">", ">gv", { desc = "Indent in and keeps the selection" })
vim.keymap.set("n", "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
vim.keymap.set("n", "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })

vim.api.nvim_create_autocmd("FileType", {
  callback = function(args)
    if args.match == "markdown" or args.match == "org-preview" then
      return
    end
    pcall(vim.treesitter.start, args.buf)
  end,
})

-- [[ Configure LSP ]]
-- vim.lsp.set_log_level("debug")
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserLspConfig", {}),
  callback = function(ev)
    vim.bo[ev.buf].omnifunc = "v:lua.vim.lsp.omnifunc"
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    client.server_capabilities.semanticTokensProvider = nil

    -- Buffer local mappings.
    -- See `:help vim.lsp.*` for documentation on any of the below functions
    local opts = { buffer = ev.buf }
    vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
    vim.keymap.set({ "v", "n" }, "<leader>co", vim.lsp.buf.code_action, opts)
    vim.keymap.set({ "v", "n" }, "<leader>cp", require("actions-preview").code_actions, opts)

    vim.keymap.set("n", "gd", require("telescope.builtin").lsp_definitions, opts)
    vim.keymap.set("n", "gr", require("telescope.builtin").lsp_references, opts)
    vim.keymap.set("n", "gI", require("telescope.builtin").lsp_implementations, opts)
    vim.keymap.set("n", "<leader>D", require("telescope.builtin").lsp_type_definitions, opts)
    -- <leader>fs, not <leader>ds: <leader>d is the black-hole delete operator.
    vim.keymap.set("n", "<leader>fs", require("telescope.builtin").lsp_document_symbols,
      { buffer = ev.buf, desc = "Document symbols" })
    vim.keymap.set("n", "<leader>ws", require("telescope.builtin").lsp_dynamic_workspace_symbols, opts)

    -- See `:help K` for why this keymap
    vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
    -- <leader>ch, not <leader>kh: <leader>k is lprev.
    vim.keymap.set("n", "<leader>ch", vim.lsp.buf.signature_help, { buffer = ev.buf, desc = "Signature help" })

    -- Lesser used LSP functionality
    vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
    vim.keymap.set("n", "<leader>wa", vim.lsp.buf.add_workspace_folder, opts)
    vim.keymap.set("n", "<leader>wr", vim.lsp.buf.remove_workspace_folder, opts)
    vim.keymap.set("n", "<leader>wl", function()
      print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
    end, opts)

    -- Create a command `:Format` local to the LSP buffer
    vim.api.nvim_buf_create_user_command(ev.buf, "Format", function(_)
      vim.lsp.buf.format()
    end, { desc = "Format current buffer with LSP" })
    vim.keymap.set({ "x", "n" }, "<leader>fo", vim.lsp.buf.format, opts)
  end,
})

local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require("cmp_nvim_lsp").default_capabilities(capabilities)

vim.api.nvim_create_autocmd("FileType", {
  pattern = "json",
  callback = function(ev)
    vim.bo[ev.buf].formatprg = "jq"
    vim.bo[ev.buf].formatexpr = ""
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "java" },
  callback = function()
    local root_dir = vim.fs.dirname(vim.fs.find({ ".git", "pom.xml", "mvnw", "gradlew" }, { upward = true })[1])
    local workspace_dir = vim.fn.expand("~/.cache/jdtls/") .. vim.fn.fnamemodify(root_dir, ":t")
    local config = {
      cmd = { "jdtls", "--data", workspace_dir },
      capabilities = capabilities,
      root_dir = root_dir,
      settings = {
        java = {
          format = {
            settings = {
              url = vim.fn.expand(
                "~/configs/nixos-configs/nixos/home-manager/common/neovim/java/formatter.xml"
              ),
              profile = "CustomProfile",
            },
          },
          completion = {
            favoriteStaticMembers = {
              "org.hamcrest.MatcherAssert.assertThat",
              "org.hamcrest.Matchers.*",
              "org.hamcrest.CoreMatchers.*",
              "org.junit.jupiter.api.Assertions.*",
              "java.util.Objects.requireNonNull",
              "java.util.Objects.requireNonNullElse",
              "org.mockito.Mockito.*",
            },
            importOrder = {
              "java",
              "javax",
              "com",
              "org",
            },
          },
        },
      },
    }
    require("jdtls").start_or_attach(config)
  end,
})

vim.lsp.config("gopls", {
  capabilities = capabilities,
  settings = {
    gopls = {
      completeUnimported = true,
      usePlaceholders = true,
      analyses = {
        unusedparams = true,
      },
    },
  },
})

vim.lsp.config("lua_ls", {
  settings = {
    Lua = {
      diagnostics = {
        globals = {
          "vim",
        },
      },
    },
  },
})
vim.lsp.config("nil_ls", {
  capabilities = capabilities,
})
-- Hybrid mode: vue_ls only handles .vue buffers and forwards their TypeScript
-- requests to ts_ls, which attaches to .vue too and runs @vue/typescript-plugin.
vim.lsp.config("vue_ls", {
  capabilities = capabilities,
  filetypes = { "vue" },
})
vim.lsp.config("ts_ls", {
  capabilities = capabilities,
  init_options = {
    plugins = vim.g.vue_language_server_path and {
      {
        name = "@vue/typescript-plugin",
        location = vim.g.vue_language_server_path,
        languages = { "vue" },
      },
    } or {},
  },
  filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "vue" },
})
vim.lsp.config("sqls", {
  capabilities = capabilities,
})
vim.lsp.config("jsonls", {
  cmd = { "vscode-json-languageserver", "--stdio" },
  capabilities = capabilities,
  settings = {
    json = {
      schemas = require("schemastore").json.schemas(),
      validate = { enable = true },
    },
  },
})

vim.lsp.config("graphql", {
  capabilities = capabilities,
})

vim.lsp.config("eslint", {
  capabilities = capabilities,
})

vim.lsp.config("kotlin_language_server", {
  capabilities = capabilities,
})

vim.lsp.config("terraformls", {
  capabilities = capabilities,
})

vim.lsp.config("yamlls", {
  capabilities = capabilities,
  settings = {
    yaml = {
      schemaStore = {
        -- You must disable built-in schemaStore support if you want to use
        -- this plugin and its advanced options like `ignore`.
        enable = false,
        -- Avoid TypeError: Cannot read properties of undefined (reading 'length')
        url = "",
      },
      schemas = require("schemastore").yaml.schemas(),
    },
  },
})

vim.lsp.config("lemminx", {
  capabilities = capabilities,
  cmd = { "lemminx" },
  filetypes = { "xml", "xsd", "xsl", "xslt", "svg" },
})

vim.lsp.enable("nil_ls")
vim.lsp.enable("lemminx")
vim.lsp.enable("lua_ls")
vim.lsp.enable("vue_ls")
vim.lsp.enable("ts_ls")
vim.lsp.enable("sqls")
vim.lsp.enable("jsonls")
vim.lsp.enable("graphql")
vim.lsp.enable("eslint")
vim.lsp.enable("kotlin_language_server")
vim.lsp.enable("terraformls")
vim.lsp.enable("yamlls")
vim.lsp.enable("gopls")
vim.lsp.enable("bashls")

vim.g.firenvim_config = {
  localSettings = {
    [ [[.*]] ] = {
      cmdline = "neovim",
      priority = 0,
      selector = 'textarea:not([readonly]):not([class="handsontableInput"]), div[role="textbox"]',
      takeover = "never",
    },
    [ [[.*notion\.so.*]] ] = {
      priority = 9,
      takeover = "never",
    },
    [ [[.*docs\.google\.com.*]] ] = {
      priority = 9,
      takeover = "never",
    },
  },
}

if vim.g.started_by_firenvim == true then
  vim.o.laststatus = 0
  vim.o.showtabline = 0
  vim.o.cmdheight = 1
end

-- Avante keybindings
vim.keymap.set({ "n", "v" }, "<leader>aa", "<cmd>AvanteAsk<cr>", { desc = "Avante: Ask AI" })
vim.keymap.set("n", "<leader>at", "<cmd>AvanteToggle<cr>", { desc = "Avante: Toggle sidebar" })
vim.keymap.set("n", "<leader>af", "<cmd>AvanteFocus<cr>", { desc = "Avante: Focus window" })
vim.keymap.set({ "n", "v" }, "<leader>ae", "<cmd>AvanteEdit<cr>", { desc = "Avante: Edit with AI" })
vim.keymap.set("n", "<leader>ar", "<cmd>AvanteRefresh<cr>", { desc = "Avante: Refresh" })
vim.keymap.set("n", "<leader>ac", "<cmd>AvanteClear<cr>", { desc = "Avante: Clear chat" })
vim.keymap.set("n", "<leader>ah", "<cmd>AvanteHistory<cr>", { desc = "Avante: Chat history" })
