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

}
