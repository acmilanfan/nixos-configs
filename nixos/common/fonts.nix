{ pkgs, ... }: {

  fonts = {
    packages = with pkgs; [
      roboto
      roboto-mono
      roboto-slab
      roboto-serif
      ubuntu-classic
      nerd-fonts.roboto-mono
      corefonts
      jetbrains-mono
      font-awesome
      noto-fonts
      inter
    ];
    enableDefaultPackages = true;
  };

  fonts.fontconfig = {
    enable = true;
    antialias = true;
    hinting.enable = true;
    hinting.autohint = true;
    hinting.style = "full";
    subpixel.rgba = "rgb";
    subpixel.lcdfilter = "default";
    defaultFonts = {
      monospace = [ "RobotoMono Nerd Font SmBd" ];
      sansSerif = [ "Roboto Medium" ];
      serif = [ "Roboto Slab Medium" "Inter" ];
      # monospace = [ "JetBrains Mono" ];
    };
  };

  i18n.extraLocaleSettings = {
    LC_TIME = "de_DE.UTF-8";
    LC_ALL = "en_US.UTF-8";
  };

}
