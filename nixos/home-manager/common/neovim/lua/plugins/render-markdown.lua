require("render-markdown").setup({
  pipe_table = { wrap = true },
})

local group = vim.api.nvim_create_augroup("MarkdownPreview", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "markdown",
  callback = function()
    require("plugins.org.preview").setup_buffer(vim.api.nvim_get_current_buf())
  end,
})
