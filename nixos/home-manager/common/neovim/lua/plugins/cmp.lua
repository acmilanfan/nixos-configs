local has_words_before = function()
    unpack = unpack or table.unpack
    local line, col = unpack(vim.api.nvim_win_get_cursor(0))
    return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
end

local cmp = require("cmp")
local luasnip = require("luasnip")
require("luasnip.loaders.from_vscode").lazy_load()
luasnip.config.setup({})
cmp.setup({
    preselect = cmp.PreselectMode.None,
    snippet = {
        expand = function(args)
            luasnip.lsp_expand(args.body)
        end,
    },
    -- experimental = {
    --     ghost_text = { hlgroup = "Comment" },
    -- },
    mapping = cmp.mapping.preset.insert({
        ["<C-n>"] = cmp.mapping.select_next_item(),
        ["<C-p>"] = cmp.mapping.select_prev_item(),
        ["<C-d>"] = cmp.mapping.scroll_docs(-4),
        ["<C-f>"] = cmp.mapping.scroll_docs(4),
        ["<Tab>"] = function(fallback)
            if not cmp.select_next_item() then
                if vim.bo.buftype ~= "prompt" and has_words_before() then
                    cmp.complete()
                elseif luasnip.expand_or_locally_jumpable() then
                    luasnip.expand_or_jump()
                else
                    fallback()
                end
            end
        end,
        ["<S-Tab>"] = function(fallback)
            if not cmp.select_prev_item() then
                if vim.bo.buftype ~= "prompt" and has_words_before() then
                    cmp.complete()
                elseif luasnip.locally_jumpable(-1) then
                    luasnip.jump(-1)
                else
                    fallback()
                end
            end
        end,
        -- ["<Tab>"] = cmp.mapping(function(fallback)
        --     if cmp.visible() then
        --         cmp.select_next_item()
        --     elseif luasnip.expand_or_locally_jumpable() then
        --         luasnip.expand_or_jump()
        --     else
        --         fallback()
        --     end
        -- end, { "i", "s" }),
        -- ["<S-Tab>"] = cmp.mapping(function(fallback)
        --     if cmp.visible() then
        --         cmp.select_prev_item()
        --     elseif luasnip.locally_jumpable(-1) then
        --         luasnip.jump(-1)
        --     else
        --         fallback()
        --     end
        -- end, { "i", "s" }),
        ["<C-Space>"] = cmp.mapping.complete({}),
        -- ['<C-Space>'] = cmp.mapping.confirm {
        --     behavior = cmp.ConfirmBehavior.Insert,
        --     select = true,
        -- },
        ["<CR>"] = cmp.mapping.confirm({
            behavior = cmp.ConfirmBehavior.Insert,
            -- TODO: add replace on a separate keybind
            -- behavior = cmp.ConfirmBehavior.Replace,
            select = true,
        }),
        ["<A-Space>"] = require("minuet").make_cmp_map(),
    }),
    sources = {
        { name = "minuet" },
        { name = "nvim_lsp" },
        { name = "luasnip" },
        { name = "nvim_lua" },
        { name = "buffer" },
        { name = "tmux" },
        { name = "emoji" },
        { name = "orgmode" },
    },
    performance = {
        fetching_timeout = 2000,
    },
    -- formatting = { source_names = { codeium = "(Codeium)" } },
})

cmp.setup.cmdline(":", {
    sources = cmp.config.sources({
        { name = "fuzzy_path" },
    }),
})
