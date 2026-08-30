{ pkgs, ... }: {

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      side-by-side = true;
      line-numbers = true;
    };
  };

  programs.git = {
    enable = true;
    settings = {
      user.name = "Andrei Shumailov";
      pull.rebase = true;
      push.autoSetupRemote = true;
      init.defaultBranch = "main";
      merge.conflictstyle = "zdiff3";
      diff.algorithm = "histogram";
      rerere.enabled = true;
    };
  };

  # Global gitignore (git reads $XDG_CONFIG_HOME/git/ignore automatically).
  # nix-direnv drops its flake-profile cache into every project using
  # `use flake` - keep it out of git status across all repos.
  home.file.".config/git/ignore".text = ''
    # nix-direnv cache (flake profile + dumped environment)
    .direnv/
  '';

}
