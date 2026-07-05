{ pkgs, ... }: {

  networking.networkmanager.enable = true;
  networking.useDHCP = false;

  networking.networkmanager.wifi.backend = "iwd";
  networking.networkmanager.wifi.powersave = false;

  networking.wireless.iwd.enable = true;

  # services.globalprotect.enable = true;
  # environment.systemPackages = with pkgs; [ globalprotect-openconnect gp-saml-gui ];
}
