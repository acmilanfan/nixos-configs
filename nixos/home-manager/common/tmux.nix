{ pkgs, lib, ... }: {

  programs.tmux = {
    enable = true;
    mouse = true;
    # Use system zsh on macOS (in /etc/shells) and nix zsh on Linux
    shell = if pkgs.stdenv.isDarwin then "/bin/zsh" else "${pkgs.zsh}/bin/zsh";
    terminal = "xterm-256color";
    clock24 = true;
    baseIndex = 1;
    escapeTime = 0;
    keyMode = "vi";
    extraConfig = lib.readFile ./tmux/tmux.conf;
    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
      # vim-tmux-navigator
      tmux-fzf
      resurrect
      continuum
      jump
      better-mouse-mode
      prefix-highlight
      urlview
      # { plugin = inputs.minimal-tmux.packages.${pkgs.system}.default; }
    ];
  };

}
