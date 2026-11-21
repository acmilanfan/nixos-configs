{ pkgs, lib, ... }:
let
  ybMode = pkgs.writeShellScriptBin "yb-mode" (
    builtins.replaceStrings
      [ "@WVKBD@" ]
      [ "${pkgs.wvkbd-top}/bin/wvkbd-mobintl" ]
      (lib.readFile ../../home-manager/common/scripts/yb-mode)
  );
  ybModePath = lib.makeBinPath [
    pkgs.bash
    pkgs.coreutils
    pkgs.hyprland
    pkgs.jq
    pkgs.procps
    pkgs.swaybg
    pkgs.systemd
    pkgs.waybar
    pkgs.wvkbd
    pkgs.yb-touchpad
  ];
in
{
  home.packages = [ pkgs.yb-touchpad pkgs.swaybg ybMode ];

  systemd.user.services.yb-mode = {
    Unit = {
      Description = "Yoga Book dock-state watcher and mode selector";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${ybMode}/bin/yb-mode daemon";
      Environment = [
        "PATH=${ybModePath}"
        "YB_MODE_KEYBOARD_PERCENT=58"
      ];
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install = {
      WantedBy = [ "hyprland-session.target" ];
    };
  };

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
