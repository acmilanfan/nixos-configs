{ pkgs, ... }: {

  services.xserver.desktopManager.plasma5.enable = true;
  services.xserver.displayManager.sddm.enable = true;

  environment.systemPackages = with pkgs; [
    libsForQt5.bismuth
    libsForQt5.plasma-browser-integration
    okular
    krita
    gwenview
    kate
    ark
    kdialog
    hspell
    krunner-pass
  ];

  hardware.bluetooth.enable = true;

  programs.kdeconnect.enable = true;
  programs.dconf.enable = true;

}
