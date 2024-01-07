{ pkgs, ... }: {

  networking.networkmanager.enable = true;
  networking.useDHCP = false;

  networking.networkmanager.wifi.powersave = false;

  services.globalprotect.enable = true;
  environment.systemPackages = with pkgs; [ globalprotect-openconnect gp-saml-gui ];
}
