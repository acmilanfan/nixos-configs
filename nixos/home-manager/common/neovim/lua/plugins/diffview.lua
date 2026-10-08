-- Review agent changes. Agent turns come from `agent-checkpoint`, which the
-- Claude/opencode hooks call before and after every turn; both ends of a turn
-- are snapshot commits, so the view also shows files the agent created.
local function close_view()
  vim.cmd("DiffviewClose")
end

require("diffview").setup({
  enhanced_diff_hl = true,
  keymaps = {
    view = { { "n", "q", close_view, { desc = "Close diffview" } } },
    file_panel = { { "n", "q", close_view, { desc = "Close diffview" } } },
    file_history_panel = { { "n", "q", close_view, { desc = "Close diffview" } } },
  },
  hooks = {
    -- `prefix D` in tmux opens nvim just for the review; leave with the view
    view_closed = function()
      if vim.g.agent_review_popup then
        vim.cmd("qa")
      end
    end,
  },
})

local function system(cmd)
  local out = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return nil, table.concat(out, "\n")
  end
  return out
end

-- :AgentReview [turn|all]   latest turn by default, 1 = first, -1 = previous
local function agent_review(turn)
  local cmd = { "agent-checkpoint", "range" }
  if turn and turn ~= "" then
    table.insert(cmd, turn)
  end
  local out, err = system(cmd)
  if not out or not out[1] then
    vim.notify(err or "agent-checkpoint: no output", vim.log.levels.WARN)
    if vim.g.agent_review_popup then
      vim.defer_fn(function() vim.cmd("qa") end, 1500)
    end
    return
  end
  local pre, post = out[1]:match("^(%S+) (%S+)$")
  vim.cmd(("DiffviewOpen %s..%s"):format(pre, post))
end

vim.api.nvim_create_user_command("AgentReview", function(o) agent_review(o.args) end, {
  nargs = "?",
  desc = "Diff an agent turn (agent-checkpoint)",
})

-- Whole branch: merge-base with the remote default branch vs the working tree
local function branch_review()
  for _, base in ipairs({ "origin/HEAD", "origin/main", "origin/master", "main", "master" }) do
    local mb = system({ "git", "merge-base", base, "HEAD" })
    if mb and mb[1] then
      vim.cmd("DiffviewOpen " .. mb[1])
      return
    end
  end
  vim.notify("No default branch found to review against", vim.log.levels.WARN)
end

local map = function(l, r, desc)
  vim.keymap.set("n", l, r, { desc = desc })
end
map("<leader>gat", function() agent_review() end, "Agent: review last turn")
map("<leader>gaa", function() agent_review("all") end, "Agent: review whole session")
map("<leader>gan", function()
  vim.ui.input({ prompt = "Turn (1.., -1, all): " }, function(t)
    if t and t ~= "" then
      agent_review(t)
    end
  end)
end, "Agent: review turn N")
map("<leader>gr", branch_review, "Review branch vs merge-base")
map("<leader>gH", "<cmd>DiffviewFileHistory %<cr>", "File history")
map("<leader>gq", close_view, "Close diffview")

