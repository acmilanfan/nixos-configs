{ pkgs, lib, unstable, ... }: {

  programs.tmux = {
    enable = true;
    mouse = true;
    shell = "${pkgs.zsh}/bin/zsh";
    terminal = "screen-256color";
    clock24 = true;
    baseIndex = 1;
    escapeTime = 0;
    sensibleOnTop = true;
    extraConfig = lib.readFile ./tmux/tmux.conf;
    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
      vim-tmux-navigator
      nord
      tmux-fzf
    ];
  };

  home.packages = [
    unstable.tmux-sessionizer
  ];

  xdg.configFile = {
    "tms/default-config.toml".source = ./../../../dotfiles/tms/config.toml;
  };

}
