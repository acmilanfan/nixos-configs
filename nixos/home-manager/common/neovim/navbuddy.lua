lua << EOF

local navbuddy = require("nvim-navbuddy")

navbuddy.setup {
    window = {
        border = "rounded",  -- "rounded", "double", "solid", "none"
    },
    lsp = {
        auto_attach = true,   -- If set to true, you don't need to manually use attach function
    },
}

EOF
