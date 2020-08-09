{ ... }: {

  services.redshift = {
    enable = true;
    provider = "geoclue2";
    tray = true;
    temperature = {
      day = 6000;
      night = 2400;
    };
  };

}
