{ pkgs, ... }: {

  services.xserver.desktopManager.gnome.enable = true;
  services.xserver.displayManager.gdm.enable = true;

  environment.systemPackages = with pkgs; [
    gnome.adwaita-icon-theme
    gnome.gnome-themes-extra
    gnome.gnome-power-manager
    gnome.gnome-screenshot
  ];

  environment.gnome.excludePackages = with pkgs.gnome3; [
    totem
    gnome-software
    cheese
    geary
    gnome-contacts
    gnome-calendar
    gnome-maps
    gnome-music
    seahorse
    simple-scan
  ];

}
