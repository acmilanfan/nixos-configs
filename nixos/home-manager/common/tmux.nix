{ pkgs, lib, ... }:
let
  tmuxUpdateEnv = pkgs.writeShellScriptBin "tmux-update-env" ''
    SOCK=$(tmux show-environment -g SSH_AUTH_SOCK | cut -d= -f2)
    if [ -n "$SOCK" ] && [ -S "$SOCK" ]; then
        mkdir -p "$HOME/.ssh"
        ln -sf "$SOCK" "$HOME/.ssh/ssh_auth_sock"
    fi
  '';

  tmux-agent-indicator = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "agent-indicator";
    version = "unstable-2026-02-23";
    src = pkgs.fetchFromGitHub {
      owner = "accessd";
      repo = "tmux-agent-indicator";
      rev = "main";
      hash = "sha256-l5ceGR7JVKuiaGobPQyhON0jOjITf77zdWhs/sjk/uw=";
    };
    postInstall = ''
      cd $out/share/tmux-plugins/agent-indicator
      ln -s agent-indicator.tmux agent_indicator.tmux
    '';
  };
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
      { plugin = tmux-agent-indicator; }
      # { plugin = inputs.minimal-tmux.packages.${pkgs.system}.default; }
    ];
  };

  home.packages = [
    tmuxUpdateEnv
    (pkgs.writeShellScriptBin "agent-state" ''
      "${tmux-agent-indicator}/share/tmux-plugins/agent-indicator/scripts/agent-state.sh" "$@"

      # Notify Hammerspoon of agent state changes for hs.alert notifications
      AGENT="" STATE=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --agent) AGENT="$2"; shift 2 ;;
          --state) STATE="$2"; shift 2 ;;
          *) shift ;;
        esac
      done
      if [ -n "$AGENT" ] && [ -n "$STATE" ]; then
        ${lib.optionalString pkgs.stdenv.isDarwin ''
          hs -c "require('nanowm.agents').onAgentStateChange('$STATE', '$AGENT')" 2>/dev/null &
        ''}
      fi
    '')
  ];

}
