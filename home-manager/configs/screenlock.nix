{ pkgs, ... }: {

    services.screen-locker = {
        enable = true;
        xautolock.enable = true;
        lockCmd = "${pkgs.i3lock}/bin/i3lock -n -c 000000";
    };
    home.packages = with pkgs; [ i3lock ];
#  services.xscreensaver = {
#    enable = true;
#    settings = {
#      mode = "blank";
#      lock = true;
#      fadeSeconds = 10;
#      lockTimeout = 10;
#    };
#  };

}
