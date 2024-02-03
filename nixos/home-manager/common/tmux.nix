{ pkgs, lib, ... }: {

  programs.tmux = {
    enable = true;
    mouse = true;
    shell = "${pkgs.zsh}/bin/zsh";
    terminal = "screen-256color";
    clock24 = true;
    baseIndex = 1;
    escapeTime = 0;
    keyMode = "vi";
    extraConfig = lib.readFile ./tmux/tmux.conf;
    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
      vim-tmux-navigator
      tmux-fzf
      {
        plugin = dracula;
        extraConfig = ''
          set -g @dracula-plugins "git"
          set -g @dracula-refresh-rate 10
          set -g @dracula-show-left-icon session
        '';
      }
    ];
  };

}
