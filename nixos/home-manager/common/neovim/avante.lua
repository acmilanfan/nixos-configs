lua << EOF

require("avante_lib").load()
require("avante").setup({
  provider = "claude", --chat
  -- auto_suggestions_provider = "mistral",
  hints = { enabled = false },
  providers = {
    claude = {
      endpoint = "AI_PROXY_CLAUDE",
      model = "claude-sonnet-4-20250514",
      timeout = 30000,
      extra_request_body = {
        temperature = 0
      },
    },
    openai = {
      endpoint = "AI_PROXY_OPENAI",
      model = "gpt-4o-mini",
      timeout = 30000,
      extra_request_body = {
        temperature = 0
      },
    },
  },
})

EOF
