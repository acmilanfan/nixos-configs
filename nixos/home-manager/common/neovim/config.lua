vim.g.mapleader = " "
vim.g.maplocalleader = " "
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
vim.o.updatetime = 50
vim.o.colorcolumn = "120"
vim.o.wrap = false
vim.wo.number = true
vim.wo.relativenumber = true
vim.wo.cursorline = true

-- [[ Highlight on yank ]]
-- See `:help vim.highlight.on_yank()`
local highlight_group = vim.api.nvim_create_augroup("YankHighlight", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function()
    vim.highlight.on_yank()
  end,
  group = highlight_group,
  pattern = "*",
})

local bufwritegroup = vim.api.nvim_create_augroup("BufWriteGroup", {})
vim.api.nvim_create_autocmd({ "BufWritePre" }, {
  group = bufwritegroup,
  pattern = "*",
  command = [[%s/\s\+$//e]],
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
vim.keymap.set("n", "<Leader>aa", builtin.keymaps, {})
vim.keymap.set("n", "<Leader>ac", builtin.commands, {})
vim.keymap.set("n", "<leader>fw", builtin.grep_string, { desc = "[S]earch current [W]ord" })
vim.keymap.set("n", "<leader>fd", builtin.diagnostics, { desc = "[S]earch [D]iagnostics" })
vim.keymap.set("n", "<leader>fr", builtin.resume, { desc = "[S]earch [R]esume" })
vim.keymap.set("n", "<leader>?", builtin.oldfiles, { desc = "[?] Find recently opened files" })
vim.keymap.set("n", "<leader>gf", builtin.git_files, { desc = "Search [G]it [F]iles" })
vim.keymap.set("n", "<leader>/", function()
  -- You can pass additional configuration to telescope to change theme, layout, etc.
  builtin.current_buffer_fuzzy_find(require("telescope.themes").get_dropdown({
    winblend = 10,
    previewer = false,
  }))
end, { desc = "[/] Fuzzily search in current buffer" })

local hop = require("hop")
local directions = require("hop.hint").HintDirection
vim.keymap.set("", "f", function()
  hop.hint_char1({ direction = directions.AFTER_CURSOR, current_line_only = true })
end, { remap = true })
vim.keymap.set("", "F", function()
  hop.hint_char1({ direction = directions.BEFORE_CURSOR, current_line_only = true })
end, { remap = true })
vim.keymap.set("", "t", function()
  hop.hint_char1({ direction = directions.AFTER_CURSOR, current_line_only = true, hint_offset = -1 })
end, { remap = true })
vim.keymap.set("", "T", function()
  hop.hint_char1({ direction = directions.BEFORE_CURSOR, current_line_only = true, hint_offset = 1 })
end, { remap = true })

vim.keymap.set("n", "<leader>cn", ":IncRename ")
vim.keymap.set("n", "<leader>cw", function()
  return ":IncRename " .. vim.fn.expand("<cword>")
end, { expr = true })

vim.keymap.set("n", "<Leader>sf", ":NvimTreeToggle<cr>", { silent = true, noremap = true })
vim.keymap.set("n", "<Leader>si", ":NvimTreeFindFile<cr>", { silent = true, noremap = true })

vim.keymap.set("n", "<Leader>kk", function()
  require("notify").dismiss()
end, {})

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
vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { desc = "Go to previous diagnostic message" })
vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { desc = "Go to next diagnostic message" })
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
vim.keymap.set("n", "<leader>Y", [["+Y]])
vim.keymap.set({ "n", "v" }, "<leader>i", [["+p]])

vim.keymap.set("n", "<leader>j", "<cmd>lnext<CR>zz")
vim.keymap.set("n", "<leader>k", "<cmd>lprev<CR>zz")
vim.keymap.set("n", "<C-j>", "<cmd>cnext<CR>zz")
vim.keymap.set("n", "<C-k>", "<cmd>cprev<CR>zz")

vim.keymap.set("n", "<C-f>", "<cmd>silent !tmux neww tmux-sessionizer<CR>")

vim.keymap.set("n", "<leader>zf", ":tab split<CR>", { silent = true })
vim.keymap.set("n", "<leader>zk", ":tab close<CR>", { silent = true })

vim.keymap.set("n", "Q", "@qj")
vim.keymap.set("x", "Q", ":norm @q<CR>")
vim.keymap.set("n", "<leader>hr", "oif err != nil {<CR>}<Esc>Oreturn err<Esc>")

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

-- [[ Configure LSP ]]
-- vim.lsp.set_log_level("debug")
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserLspConfig", {}),
  callback = function(ev)
    vim.bo[ev.buf].omnifunc = "v:lua.vim.lsp.omnifunc"

    -- Buffer local mappings.
    -- See `:help vim.lsp.*` for documentation on any of the below functions
    local opts = { buffer = ev.buf }
    vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
    vim.keymap.set({ "v", "n" }, "<leader>ca", vim.lsp.buf.code_action, opts)
    vim.keymap.set({ "v", "n" }, "<leader>cp", require("actions-preview").code_actions)

    vim.keymap.set("n", "gd", require("telescope.builtin").lsp_definitions, opts)
    vim.keymap.set("n", "gr", require("telescope.builtin").lsp_references, opts)
    vim.keymap.set("n", "gI", require("telescope.builtin").lsp_implementations, opts)
    vim.keymap.set("n", "<leader>D", require("telescope.builtin").lsp_type_definitions, opts)
    vim.keymap.set("n", "<leader>ds", require("telescope.builtin").lsp_document_symbols, opts)
    vim.keymap.set("n", "<leader>ws", require("telescope.builtin").lsp_dynamic_workspace_symbols, opts)

    -- See `:help K` for why this keymap
    vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
    vim.keymap.set("n", "<leader>kh", vim.lsp.buf.signature_help, opts)

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
  pattern = { "java" },
  callback = function()
    local config = {
      cmd = { "jdtls" },
      capabilities = capabilities,
      root_dir = vim.fs.dirname(vim.fs.find({ ".git", "pom.xml", "mvnw", "gradlew" }, { upward = true })[1]),
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

require("lspconfig").gopls.setup({
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
require("lspconfig").lua_ls.setup({
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
require("lspconfig").nil_ls.setup({
  capabilities = capabilities,
})
require("lspconfig").volar.setup({
  init_options = {
    typescript = {
      tsdk = "",
    },
  },
  capabilities = capabilities,
  filetypes = { "typescript", "javascript", "javascriptreact", "typescriptreact", "vue", "json" },
})
require("lspconfig").ts_ls.setup({
  capabilities = capabilities,
})
require("lspconfig").sqls.setup({
  capabilities = capabilities,
})
require("lspconfig").jsonls.setup({
  cmd = { "vscode-json-languageserver", "--stdio" },
  capabilities = capabilities,
  settings = {
    json = {
      schemas = require("schemastore").json.schemas(),
      validate = { enable = true },
    },
  },
})

require("lspconfig").graphql.setup({
  capabilities = capabilities,
})

require("lspconfig").eslint.setup({
  capabilities = capabilities,
})

require("lspconfig").kotlin_language_server.setup({
  capabilities = capabilities,
})

require("lspconfig").terraformls.setup({
  capabilities = capabilities,
})

require("lspconfig").yamlls.setup({
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

local lemminx_home = vim.env["LEMMINX_HOME"]
if lemminx_home then
  local common = require("utils.common")

  local lemminx_jars = {}
  for _, bundle in ipairs(vim.split(vim.fn.glob(lemminx_home .. "/*.jar"), "\n")) do
    table.insert(lemminx_jars, bundle)
  end

  local lemminxStr = vim.fn.join(lemminx_jars, common.is_win and ";" or ":")
  cmd = {
    common.java_bin(),
    "-cp",
    lemminxStr,
    "org.eclipse.lemminx.XMLServerLauncher",
  }
end
require("lspconfig").lemminx.setup({
  capabilities = capabilities,
  cmd = cmd,
})

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
