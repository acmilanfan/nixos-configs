require("avante_lib").load()
require("avante").setup({
  provider = "claude", --chat
  -- auto_suggestions_provider = "mistral",
  hints = { enabled = false },
  selection = {
    enabled = false,
  },
  behaviour = {
    enable_token_counting = false,
  },
  providers = {
    claude = {
      endpoint = vim.env.AI_PROXY_CLAUDE or "",
      api_key_name = "AI_PROXY_API_KEY",
      -- model = "claude-sonnet-4-5-20250929",
      model = "claude-opus-4-5-20251101",
      timeout = 30000,
      extra_request_body = {
        temperature = 0,
      },
      extra_headers = {
        ["User-Agent"] = "Avante",
      },
    },
    openai = {
      endpoint = vim.env.AI_PROXY_OPENAI or "",
      api_key_name = "AI_PROXY_API_KEY",
      model = "gpt-4o-mini",
      timeout = 30000,
      extra_request_body = {
        temperature = 0,
      },
      extra_headers = {
        ["User-Agent"] = "Avante",
      },
    },
  },
})
