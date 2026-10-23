{ pkgs, ... }: {

  # Wrapper that syncs the cache from/to the Nextcloud folder only while
  # newsboat is not running, so the SQLite file is never copied mid-write.
  # flock: cross-platform (macOS has none), used to serialise wrapper runs.
  home.packages = [
    (pkgs.writeShellScriptBin "newsboat-sync"
      (builtins.replaceStrings [ "@flock@" ] [ "${pkgs.flock}/bin/flock" ]
        (builtins.readFile ./newsboat-sync.sh)))
  ];

programs.newsboat = {
    enable = true;

    extraConfig = ''
      # Cross-platform browser command: uses xdg-open on Linux and falls back to open on macOS.
      browser "(command -v xdg-open >/dev/null 2>&1 && xdg-open '%u' || open '%u') & sleep 0.2"

      # Newsboat Nightfox theme. Only the terminal default and ANSI 0-15 are
      # used: those are the Nightfox palette in dotfiles/ghostty/config and
      # alacritty.nix, so newsboat follows the same colors as Neovim instead of
      # approximating them with fixed xterm indices.
      color background          default  default
      color listnormal          default  default
      color listnormal_unread   color12  default
      color listfocus           color15  color8
      color listfocus_unread    color15  color8 bold
      color info                color7   color0
      color hint-key            color11  color0 bold
      color title               color6   color0 bold
      color article             default  default
      color end-of-text-marker  color8   default

      # highlights (titles, links, references)
      highlight article "^(Feed|Link):.*$"         color6 default bold
      highlight article "^(Title|Date|Author):.*$" color6 default bold
      highlight article "https?://[^ ]+"           color4 default underline
      highlight article "\\[[0-9]+\\]"             color2 default bold
      highlight article "\\[image\\ [0-9]+\\]"     color2 default bold
      highlight feedlist "^─.*$"                   color6 color0 bold

      # keybindings
      unbind-key ENTER
      unbind-key j
      unbind-key k
      unbind-key J
      unbind-key K

      bind-key j down
      bind-key k up
      bind-key l open
      bind-key h quit
      bind-key ^A open-all-unread-in-browser-and-mark-read
    '';
  };

}
