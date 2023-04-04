{ pkgs, ... }: {

  programs.newsboat = {
    enable = true;
    extraConfig = ''
      include ${pkgs.newsboat}/share/doc/newsboat/contrib/colorschemes/nord

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
