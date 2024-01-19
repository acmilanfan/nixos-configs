{ pkgs, ... }: {

  fonts = {
    fonts = with pkgs; [
      corefonts
      fira-code
      font-awesome
      hack-font
      source-code-pro
      roboto
      roboto-mono
      roboto-slab
      ubuntu_font_family
      inconsolata
      unifont
      open-sans
      nerdfonts
#      noto-fonts
    ];
    enableDefaultFonts = true;
  };

  fonts.fontconfig = {
      hinting.autohint = true;
      hinting.style = "hintfull";
      defaultFonts = {
        monospace = [ "RobotoMono Nerd Font SemiBold 13" ];
        sansSerif = [ "Roboto SemiBold 13" ];
        serif = [ "Roboto Slab SemiBold 13" "Inter 13" ];
    };
  };

}
