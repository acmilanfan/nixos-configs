{ pkgs, lib, ... }: {

  fonts = {
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
      opensans-ttf
    ];
    enableDefaultFonts = true;
  };

  fonts.fontconfig.defaultFonts.monospace = [ "Roboto Mono" ];

}
