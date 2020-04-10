{ pkgs, ... }: {

  services.xserver.desktopManager.gnome3.enable = true;

  services.gnome3 = {
    #todo
  };

  environment.gnome3.excludePackages = with pkgs.gnome3; [
    totem
    gnome-software
    cheese
    geary
    gnome-photos
    gnome-contacts
    gnome-calendar
    gnome-maps
    gnome-music
    seahorse
    simple-scan
  ];

}
