{ ... }: {

  services.flameshot.enable = true;
  # services.safeeyes.enable = true;
  services.unclutter.enable = true;

  services.nextcloud-client = {
    enable = true;
    startInBackground = true;
  };

}
