{ pkgs, lib, ... }: {

  home.packages = [ pkgs.yb-touchpad pkgs.swaybg ];

  systemd.user.services.yb-touchpad = {
    Unit = {
      Description = "Yoga Book 9i triple-tap touchpad window daemon";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.yb-touchpad}/bin/yb-touchpad";
      Restart = "on-failure";
      RestartSec = 2;
      # /dev/uinput access (group membership comes from users.nix)
      Environment = "RUST_LOG=info";
    };
    Install = {
      WantedBy = [ "hyprland-session.target" ];
    };
  };

}
