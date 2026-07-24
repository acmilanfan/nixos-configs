require("snacks").setup({
  quickfile = { enabled = true },
  gitbrowse = {
    enabled = true,
    -- `git.nix` rewrites wkda org remotes to the "github-work" ssh alias
    -- (see ~/.ssh/config); translate it back to github.com before the
    -- built-in ssh->https patterns run, otherwise they produce
    -- https://github-work/... which isn't a resolvable URL.
    remote_patterns = {
      { "^git@github%-work:(.+)$", "git@github.com:%1" },
      { "^(https?://.*)%.git$", "%1" },
      { "^git@(.+):(.+)%.git$", "https://%1/%2" },
      { "^git@(.+):(.+)$", "https://%1/%2" },
      { "^git@(.+)/(.+)$", "https://%1/%2" },
      { "^org%-%d+@(.+):(.+)%.git$", "https://%1/%2" },
      { "^ssh://git@(.*)$", "https://%1" },
      { "^ssh://([^:/]+)(:%d+)/(.*)$", "https://%1/%3" },
      { "^ssh://([^/]+)/(.*)$", "https://%1/%2" },
      { "ssh%.dev%.azure%.com/v3/(.*)/(.*)$", "dev.azure.com/%1/_git/%2" },
      { "^https://%w*@(.*)", "https://%1" },
      { "^git@(.*)", "https://%1" },
      { ":%d+", "" },
      { "%.git$", "" },
    },
  },
})
