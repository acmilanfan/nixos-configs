{ ... }: {

  networking.networkmanager.enable = true;
  networking.useDHCP = false;

  networking.networkmanager.wifi.powersave = false;
}
