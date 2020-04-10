{ pkgs, ... }: {

  services.xserver.displayManager.gdm.enable = true;
  services.xserver.displayManager.sessionCommands = "${pkgs.xorg.xhost}/bin/xhost +SI:localuser:$USER";
}
