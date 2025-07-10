lua << EOF

require("minuet").setup({
  cmp = {
    enable_auto_complete = true,
  },
  provider = "codestral",
  provider_options = {
    codestral = {
      end_point = "AI_PROXY_MISTRAL",
      api_key = "AI_API_KEY",
    },
  },
})

EOF
