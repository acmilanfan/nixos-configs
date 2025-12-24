{ ... }: {

  services.flameshot = {
    # TODO: enable if not wayland session
    # enable = true;
    settings = {
      General = {
        showStartupLaunchMessage = false;
        useGrimAdapter = true;
      };
    };
  };
  # services.safeeyes.enable = true;
  services.unclutter.enable = true;

  services.nextcloud-client = {
    enable = true;
    startInBackground = true;
  };

}
