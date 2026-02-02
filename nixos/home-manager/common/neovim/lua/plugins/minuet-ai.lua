require("minuet").setup({
  cmp = {
    enable_auto_complete = true,
  },
  provider = "codestral",
  provider_options = {
    codestral = {
      end_point = vim.env.AI_PROXY_MISTRAL_COMPLETION or "",
      api_key = function()
        return vim.env.AI_PROXY_API_KEY or ""
      end,
    },
  },
})
