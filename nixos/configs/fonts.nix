{ pkgs, lib, ... }: {

  fonts = {
    #enableFontDir = true;
    #enableGhostscriptFonts = true;
    fonts = with pkgs; [
      corefonts
      fira-code
      font-awesome
      hack-font
      source-code-pro
      roboto
      roboto-mono
      ubuntu_font_family
      inconsolata
      unifont
    ];
  };

  fonts.fontconfig.defaultFonts.monospace = [ "Roboto Mono" ];

}
