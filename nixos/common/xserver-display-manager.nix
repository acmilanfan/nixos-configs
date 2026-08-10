{ pkgs, ... }: {

  services.xserver.desktopManager.xterm.enable = false;
  services.xserver.displayManager.sessionCommands = "${pkgs.xhost}/bin/xhost +SI:localuser:$USER";

}
