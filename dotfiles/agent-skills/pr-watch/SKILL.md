---
name: pr-watch
description: Use right after opening a pull request or pushing new commits to one, instead of polling CI or sleeping. Starts a background watcher that types a message into this session when a check fails, all checks pass, someone comments or reviews, or the PR gets a merge conflict.
metadata:
  opencode/slash: "true"
---

# Watch a PR instead of polling it

After you open a PR or push to one, start the watcher and **end your turn**:

```bash
pr-watch            # PR of the current branch
pr-watch 123        # or a PR number / URL / branch
```

It runs in the background (inside tmux, so it outlives your shell) and wakes
you later with a single line starting with `[pr-watch]`, for example:

    [pr-watch] PR #123: checks failed on abc1234: build, unit-tests. ...

When that message arrives, act on it the way the user's instructions say
(e.g. fetch the failing CI log, fix, push). Pushing again needs no new
watcher: the running one follows the PR's new head commit. It stops by
itself when the PR is merged or closed.

Rules:

- Do not poll `gh pr checks`, sleep, or loop while waiting for CI.
- Do not start a second watcher for the same PR; re-running `pr-watch` for
  it is a no-op anyway.
- `pr-watch --list` shows active watchers, `pr-watch --stop [pr]` stops one.
- It only works inside tmux (it needs `$TMUX_PANE`). Outside tmux, tell the
  user it isn't available and fall back to their usual CI workflow.
