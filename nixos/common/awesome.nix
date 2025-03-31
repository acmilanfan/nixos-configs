{ pkgs, ... }: {

  services.xserver.windowManager.awesome = {
    enable = true;
    noArgb = false;
    luaModules = [ pkgs.luaPackages.lgi ];
  };

  services.picom.enable = true;

}
