{ ... }: {

  services.flameshot = {
    enable = true;
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
