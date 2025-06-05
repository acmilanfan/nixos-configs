{ pkgs, ... }: {

  services.xserver.windowManager.awesome = {
    enable = true;
    noArgb = false;
    luaModules = [ pkgs.luaPackages.lgi ];
  };

  services.picom.enable = true;
  services.picom.settings = {
    use-damage = true;
    vsync = true;
    # shadow = true;
    # backend = "glx";
    detect-rounded-corners = true;
    respect-client-shape = true;
  };
  security.pam.services.i3lock.enable = true;

}
