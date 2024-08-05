lua << EOF

local null_ls = require("null-ls")
null_ls.setup({
    sources = {
        null_ls.builtins.formatting.stylua,
        null_ls.builtins.formatting.gofmt,
        null_ls.builtins.formatting.goimports_reviser,
        null_ls.builtins.formatting.prettier,
        null_ls.builtins.formatting.yamlfix,
        -- null_ls.builtins.formatting.fixjson,
        null_ls.builtins.formatting.nixfmt,
        -- null_ls.builtins.formatting.google_java_format,
        null_ls.builtins.formatting.golines,
        -- null_ls.builtins.diagnostics.eslint,
        null_ls.builtins.diagnostics.yamllint,
        null_ls.builtins.diagnostics.checkstyle.with({
            extra_args = { "-c", vim.fn.expand( "~/configs/nixos-configs/nixos/home-manager/common/neovim/java/checkstyle.xml") },
        }),
        null_ls.builtins.code_actions.statix,
        null_ls.builtins.code_actions.gitsigns,
        -- null_ls.builtins.code_actions.refactoring.with({
        --     filetypes = { "java", "go", "javascript", "lua", "typescript" }
        -- }),
    },
})

EOF
