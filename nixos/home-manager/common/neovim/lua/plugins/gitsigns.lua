require("gitsigns").setup({
  on_attach = function(bufnr)
    local gs = package.loaded.gitsigns
    local map = function(mode, l, r, desc)
      vim.keymap.set(mode, l, r, { buffer = bufnr, desc = desc })
    end

    -- Navigate hunks (]c/[c are free; ]d/[d are taken by diagnostics)
    map("n", "]c", function() gs.next_hunk() end, "Next git hunk")
    map("n", "[c", function() gs.prev_hunk() end, "Prev git hunk")

    -- Preview
    map("n", "<leader>gp", gs.preview_hunk_inline, "Preview hunk inline")
    map("n", "<leader>gP", gs.preview_hunk, "Preview hunk popup")

    -- Stage/reset hunks (<leader>gs is taken by telescope git_status)
    map("n", "<leader>ghs", gs.stage_hunk, "Stage hunk")
    map("n", "<leader>ghr", gs.reset_hunk, "Reset hunk")
    map("v", "<leader>ghs", function() gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, "Stage hunk (range)")
    map("v", "<leader>ghr", function() gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, "Reset hunk (range)")
    map("n", "<leader>ghS", gs.stage_buffer, "Stage buffer")
    map("n", "<leader>ghR", gs.reset_buffer, "Reset buffer")
    map("n", "<leader>ghu", gs.undo_stage_hunk, "Undo stage hunk")

    -- Blame (<leader>gB is taken by snacks gitbrowse)
    map("n", "<leader>gb", function() gs.blame_line({ full = true }) end, "Blame line")

    -- Persistent whole-file inline diff toggles (using <leader>gv* — 't' is taken by hop)
    map("n", "<leader>gvb", gs.toggle_current_line_blame, "Toggle line blame")
    map("n", "<leader>gvd", gs.toggle_deleted, "Toggle deleted lines inline")
    map("n", "<leader>gvw", gs.toggle_word_diff, "Toggle word diff inline")

    -- Diff
    map("n", "<leader>gd", gs.diffthis, "Diff this file")
  end,
})
