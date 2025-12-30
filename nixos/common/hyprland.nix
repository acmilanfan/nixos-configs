{ pkgs, ... }: {

  programs.hyprland.enable = true;

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

  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];

  # programs.hyprland = {
  #   enable = true;
  #   xwayland.enable = true;
  # };
  security.pam.services.hyprlock.enable = true;

  programs.iio-hyprland.enable = true;

}
