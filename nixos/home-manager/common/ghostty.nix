{ pkgs, ... }: {
  home.packages = [
    (if pkgs.stdenv.isDarwin then pkgs.ghostty-bin else pkgs.ghostty)
  ];

  xdg.configFile."ghostty/config" = {
    source = ../../../dotfiles/ghostty/config;
    force = true;
  };
}
