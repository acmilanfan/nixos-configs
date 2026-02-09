{ pkgs, lib, ... }:
let
  tmuxUpdateEnv = pkgs.writeShellScriptBin "tmux-update-env" ''
    SOCK=$(tmux show-environment -g SSH_AUTH_SOCK | cut -d= -f2)
    if [ -n "$SOCK" ] && [ -S "$SOCK" ]; then
        mkdir -p "$HOME/.ssh"
        ln -sf "$SOCK" "$HOME/.ssh/ssh_auth_sock"
    fi
  '';
in
{

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
    extraConfig = ''
      ${lib.readFile ./tmux/tmux.conf}
      set-hook -g client-attached 'run-shell "${tmuxUpdateEnv}/bin/tmux-update-env"'
    '';
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

  home.packages = [ tmuxUpdateEnv ];

}
