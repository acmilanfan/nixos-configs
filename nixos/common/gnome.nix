{ pkgs, ... }: {

  services.xserver.desktopManager.gnome.enable = true;
  services.xserver.displayManager.gdm.enable = true;

  environment.systemPackages = with pkgs; [
    adwaita-icon-theme
    gnome-themes-extra
    gnome-power-manager
    gnome-screenshot
    gnome-tweaks
  ];

  environment.gnome.excludePackages = with pkgs; [
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
