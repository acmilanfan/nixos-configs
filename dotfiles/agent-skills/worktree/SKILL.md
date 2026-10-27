---
name: worktree
description: Use when the user asks for a new git worktree, a branch to work on in parallel, or to hand a task to another agent in its own worktree, and when switching to or removing such a worktree. Covers this machine's wt-new, worktree-switch and worktree-remove commands, which run without prompting when given flags.
---

# Worktrees on this machine

Worktrees are siblings of the main checkout: `<parent>/<repo>-<branch>`
(a `/` in the branch becomes `-`). Their tmux session has the same name,
with `.` replaced by `_`. Use these commands rather than plain
`git worktree add`: `wt-new` also links `.env`/`.envrc` and agent
permissions and runs the repo's setup script.

None of them prompt when stdin is not a terminal (your shell tool), so pass
everything as flags.

## Create: `wt-new`

```bash
wt-new -b feat/x                                # worktree only; prints its path
wt-new -b feat/x --base origin/master           # new branch from a given ref
wt-new -t "CFE-123 fix the vin check" -a claude # branch named from the task,
                                                # claude started with it as prompt
wt-new -C ~/Projects/repo -b fix -a shell       # another repo; tmux session only
```

- `-t/--task` names the branch with `ai-branch-name` (takes up to ~40 s)
  unless `-b` is given, and is the agent's first prompt.
- `-a/--agent`: `none` (default without a terminal), `shell`, `claude`,
  `opencode`, `antigravity`. With an agent the tmux session is created
  detached; `--switch` moves the user's client to it, so only use that when
  they asked.
- `-m/--models omlx|qwen` starts local models for `opencode`.
- stdout is only the worktree path; progress goes to stderr. Re-running for
  the same branch reuses the worktree.

## Switch and remove

```bash
worktree-switch feat/x            # print the path (by branch, dir name or path)
worktree-switch --claude feat/x   # session + claude in it
worktree-remove feat/x            # keeps it if it has changes, and says so
worktree-remove --force --kill-session feat/x
```

Rules:

- Ask before `worktree-remove --force`: it discards uncommitted and
  untracked work. Check `git -C <path> status` first.
- Don't use `--kill-session` on the session you are running in.
