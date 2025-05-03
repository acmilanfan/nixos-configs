{ pkgs, ... }: {

  programs.newsboat = {
    enable = true;
    extraConfig = ''
      # Newsboat Nightfox theme (approximate with 256-color codes)
      color background          color234  default
      color listnormal          color243  default
      color listnormal_unread   color68   default
      color listfocus           color234  color68
      color listfocus_unread    color234  color68 bold
      color info                color81   color234
      color article             color252  default
      color title               color80   default bold

      # highlights (titles, links, references)
      highlight article "^(Feed|Link):.*$"         color80 default bold
      highlight article "^(Title|Date|Author):.*$" color80 default bold
      highlight article "https?://[^ ]+"           color80 default underline
      highlight article "\\[[0-9]+\\]"             color108 default bold
      highlight article "\\[image\\ [0-9]+\\]"     color108 default bold
      highlight feedlist "^─.*$"                   color80 color234 bold

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
    '';
  };

}
