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

  # macOS-style font rendering:
  # - no hinting (preserve original glyph geometry)
  # - grayscale antialiasing (no RGB subpixel / LCD filtering)
  # - FreeType stem darkening re-enabled via FREETYPE_PROPERTIES below
  fonts.fontconfig = {
    enable = true;
    antialias = true;
    hinting.enable = false;
    subpixel.rgba = "none";
    subpixel.lcdfilter = "none";
    defaultFonts = {
      monospace = [ "RobotoMono Nerd Font SmBd" ];
      sansSerif = [ "Inter" ];
      serif = [ "Roboto Slab Medium" "Inter" ];
      # monospace = [ "JetBrains Mono" ];
    };
  };

  # Re-enable FreeType stem darkening (disabled by default since FreeType 2.7).
  # Thickens glyph stems to compensate for the lighter look of grayscale AA —
  # the main ingredient of macOS-style text weight.
  environment.sessionVariables.FREETYPE_PROPERTIES =
    "cff:no-stem-darkening=0 autofitter:no-stem-darkening=0 type1:no-stem-darkening=0 t1cid:no-stem-darkening=0";

  i18n.extraLocaleSettings = {
    LC_TIME = "de_DE.UTF-8";
    LC_ALL = "en_US.UTF-8";
  };

}
