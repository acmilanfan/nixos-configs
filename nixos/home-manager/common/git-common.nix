{ pkgs, ... }: {

  programs.git = {
    enable = true;
    userName = "Andrei Shumailov";
    delta = {
      enable = true;
      options = {
        navigate = true;
        side-by-side = true;
        line-numbers = true;
      };
    };
    extraConfig = {
      pull.rebase = true;
      push.autoSetupRemote = true;
      init.defaultBranch = "main";
      merge.conflictstyle = "zdiff3";
      diff.algorithm = "histogram";
      rerere.enabled = true;
    };
  };

}
