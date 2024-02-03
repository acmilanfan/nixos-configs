lua << EOF

local null_ls = require("null-ls")
null_ls.setup({
    sources = {
        null_ls.builtins.formatting.stylua,
        null_ls.builtins.formatting.gofumpt,
        null_ls.builtins.formatting.goimports_reviser,
        null_ls.builtins.formatting.prettier,
        null_ls.builtins.formatting.yamlfix,
        null_ls.builtins.formatting.fixjson,
        null_ls.builtins.formatting.nixfmt,
        -- null_ls.builtins.formatting.google_java_format,
        null_ls.builtins.formatting.golines,
        null_ls.builtins.diagnostics.eslint,
        null_ls.builtins.diagnostics.yamllint,
        null_ls.builtins.code_actions.statix,
        null_ls.builtins.code_actions.gitsigns,
        -- null_ls.builtins.diagnostics.checkstyle, TODO: fix for java or settle for google checkstyle`
    },
})

EOF
