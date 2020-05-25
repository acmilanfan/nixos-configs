{ pkgs, ... }: {

  services.xserver.windowManager.awesome = {
    enable = true;
    noArgb = true;
    luaModules = [ pkgs.luaPackages.lgi ];
  };

}
