{ pkgs, ... }: {

  gtk = {
    enable = true;
    font = {
      name = "Roboto Medium";
      size = 13;
      package = pkgs.roboto;
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

  fonts.fontconfig.enable = false;

}
