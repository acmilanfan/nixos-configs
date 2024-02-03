{ pkgs, ... }: {

  home.packages = with pkgs; [
    zsh-you-should-use
  ];

  programs.zsh = {
    enable = true;
    enableAutosuggestions = true;
    syntaxHighlighting.enable = true;
    defaultKeymap = "viins";
    autocd = true;
    plugins = [
      {
        name = "zsh-nix-shell";
        src = pkgs.zsh-nix-shell;
      }
    ];
    shellAliases = {
      ll = "ls -l";
      gs = "git status";
      gp = "git pull";
      alacritty = "WINIT_X11_SCALE_FACTOR=1.3 alacritty";
      oi = "cd ~/org/life && vim ~/org/life/index.org";
      yt = "cd ~/org/consume && vim ~/org/consume/youtube/youtube1.org";
      os = "(cd ~/org && git pull)";
      op = "(cd ~/org && git add . && git commit -m \"Sync\" && git push)";
      up = "cd $HOME/configs/nixos-configs && nix flake update";
      sup = "sudo nixos-rebuild switch --flake $HOME/configs/nixos-configs/#$NIX_SYSTEM --impure";
      nb = "newsboat --url-file=~/org/rss --cache-file=~/Nextcloud/newsboat/cache.db";
      java-shell = "nix develop ~/configs/nixos-configs/shell/java";
      go-shell = "nix develop ~/configs/nixos-configs/shell/go-node";
      fhs-shell = "nix develop ~/configs/nixos-configs/shell/fhs";
    };
    initExtra = ''
      autoload -U colors && colors
      PS1="%B%{$fg[cyan]%}$IN_NIX_SHELL%{$fg[red]%}[%{$fg[yellow]%}%n%{$fg[green]%}@%{$fg[blue]%}%M %{$fg[magenta]%}%~%{$fg[red]%}]%{$reset_color%}$%b "

      zstyle ':completion:*' menu select
      zmodload zsh/complist
      compinit
      _comp_options+=(globdots)

      export FZF_DEFAULT_OPTS='--color=fg:#f8f8f2,bg:#282a36,hl:#bd93f9 --color=fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9 --color=info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6 --color=marker:#ff79c6,spinner:#ffb86c,header:#6272a4'
      export TERM='xterm-256color'

      # Use vim keys in tab complete menu
      export KEYTIMEOUT=1
      bindkey -M menuselect 'h' vi-backward-char
      bindkey -M menuselect 'k' vi-up-line-or-history
      bindkey -M menuselect 'l' vi-forward-char
      bindkey -M menuselect 'j' vi-down-line-or-history
      bindkey -v '^?' backward-delete-char
      # Change cursor shape for different vi modes.
      function zle-keymap-select {
        if [[ ''${KEYMAP} == vicmd ]] ||
           [[ $1 = 'block' ]]; then
          echo -ne '\e[1 q'
        elif [[ ''${KEYMAP} == main ]] ||
             [[ ''${KEYMAP} == viins ]] ||
             [[ ''${KEYMAP} = \'\' ]] ||
             [[ $1 = 'beam' ]]; then
          echo -ne '\e[5 q'
        fi
      }
      zle -N zle-keymap-select
      zle-line-init() {
          zle -K viins # initiate `vi insert` as keymap (can be removed if `bindkey -V` has been set elsewhere)
          echo -ne "\e[5 q"
      }
      zle -N zle-line-init
      echo -ne '\e[5 q' # Use beam shape cursor on startup.
      preexec() { echo -ne '\e[5 q' ;} # Use beam shape cursor for each new prompt.

      # Use lf to switch directories and bind it to ctrl-o
      lfcd () {
          tmp="$(mktemp)"
          lf -last-dir-path="$tmp" "$@"
          if [ -f "$tmp" ]; then
              dir="$(cat "$tmp")"
              rm -f "$tmp"
              [ -d "$dir" ] && [ "$dir" != "$(pwd)" ] && cd "$dir"
          fi
      }
      bindkey -s '^o' 'lfcd\n'

      # Edit line in vim with ctrl-e:
      autoload edit-command-line; zle -N edit-command-line
      bindkey '^e' edit-command-line
    '';
  };

}
