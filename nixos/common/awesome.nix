{ pkgs, ... }: {

  services.xserver.windowManager.awesome = {
    enable = true;
    noArgb = false;
    luaModules = [ pkgs.luaPackages.lgi ];
  };

  services.picom.enable = true;
  security.pam.services.i3lock.enable = true;

}
