{ pkgs, ... }: {

  services.screen-locker = {
    enable = true;
    inactiveInterval = 5;
    xautolock.enable = true;
    xautolock.extraOptions = [
      "-locker try-lock"
      "-notify 30"
      "-notifier ${
        pkgs.writeShellScriptBin "notify-wrapper" ''
          #!/usr/bin/env bash
          exec notify-send -u critical -t 30000 "LOCKING screen in 30 seconds!" "$@"
        ''
      }/bin/notify-wrapper"
    ];
    lockCmd = "${pkgs.i3lock}/bin/i3lock -n -c 000000";

  };
  home.packages = with pkgs; [ i3lock procps ];

}
