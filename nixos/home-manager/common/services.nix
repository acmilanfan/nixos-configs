{ config, ... }: {

  services.flameshot = {
    enable = !config.wayland.windowManager.hyprland.enable;
    settings = {
      General = {
        showStartupLaunchMessage = false;
        useGrimAdapter = true;
      };
    };
  };
  # services.safeeyes.enable = true;
  services.unclutter.enable = !config.wayland.windowManager.hyprland.enable;

  services.nextcloud-client = {
    enable = true;
    startInBackground = true;
  };

}
