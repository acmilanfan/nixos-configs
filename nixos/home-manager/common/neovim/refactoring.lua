lua << EOF

require('refactoring').setup({
    prompt_func_return_type = {
        go = true,
        java = true,
    },
    prompt_func_param_type = {
        go = true,
        java = true,
    },
})

EOF
