{ pkgs, lib, ... }: {
  home.packages = [
    (if pkgs.stdenv.isDarwin then pkgs.ghostty-bin else pkgs.ghostty)
  ];

  xdg.configFile."ghostty/config" = {
    # Font size lives here so Linux matches Alacritty's 13px while macOS keeps 16.
    text = lib.readFile ../../../dotfiles/ghostty/config
      + ''
        # Platform font size (Alacritty parity: 16 macOS, 13 Linux)
        font-size = ${if pkgs.stdenv.isDarwin then "16" else "13"}
      '';
    force = true;
  };
}
