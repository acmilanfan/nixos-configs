{ pkgs, ... }: {

  services.xserver.windowManager.awesome = {
    enable = true;
    noArgb = false;
    luaModules = [ pkgs.luaPackages.lgi ];
  };

  services.picom.enable = true;
  # services.picom.settings = {
    # use-damage = false;
    # vsync = true;
    # shadow = true;
    # backend = "glx";
    # corner-radius = 10;
    # round-borders = 1;
    # detect-rounded-corners = true;
    # respect-client-shape= false;
    # rounded-corners-exclude = [ "fullscreen = true" "maximized = true" ];
  # };
  security.pam.services.i3lock.enable = true;

}
