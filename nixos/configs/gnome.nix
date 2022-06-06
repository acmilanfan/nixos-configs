{ pkgs, ... }: {

  services.xserver.desktopManager.gnome.enable = true;

  services.gnome = {
    #todo
  };

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
