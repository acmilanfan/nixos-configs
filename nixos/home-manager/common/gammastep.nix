{ ... }:
{
  services.gammastep = {
    enable = true;
    provider = "manual";
    latitude = 52.494865;
    longitude = 13.353801;
    tray = true;
    temperature = {
      day = 6000;
      night = 2400;
    };
    settings = {
      general.adjustment-method = "wayland";
    };
  };

}
