{ pkgs, ... }: {

  gtk = {
    enable = true;
    font = {
      name = "Roboto Bold";
      size = 13;
    };
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome.gnome-themes-extra;
    };
    iconTheme = {
      name = "Adwaita";
      package = pkgs.gnome.adwaita-icon-theme;
    };
  };

  fonts.fontconfig.enable = true;

}
