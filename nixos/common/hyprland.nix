{ pkgs, unstable, ... }:
{

  programs.hyprland = {
    enable = true;
    package = unstable.hyprland;
    portalPackage = unstable.xdg-desktop-portal-hyprland;
  };

  # programs.uwsm = {
  #   enable = true;
  #   waylandCompositors = { };
  # };
  #
  # services.greetd = {
  #   enable = true;
  #   settings.default_session = {
  #     command = "uwsm start hyprland";
  #     user = "gentooway";
  #   };
  # };

  services.dbus.enable = true;
  xdg.portal.enable = true;

  # The Hyprland portal comes from programs.hyprland.portalPackage.
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  # programs.hyprland = {
  #   enable = true;
  #   xwayland.enable = true;
  # };
  security.pam.services.hyprlock.enable = true;

  programs.iio-hyprland = {
    enable = true;
    package = unstable.iio-hyprland;
  };

  services.gnome.gnome-keyring.enable = true;

  security.pam.services.hyprland.enableGnomeKeyring = true;

}
