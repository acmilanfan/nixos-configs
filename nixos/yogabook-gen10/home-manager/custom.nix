{ pkgs, lib, ... }:
let
  quickshellShell = pkgs.writeShellScriptBin "hypr-quickshell-shell"
    (lib.readFile ../../home-manager/common/scripts/hypr-quickshell-shell);
  waybarToggle = pkgs.writeShellScriptBin "hypr-waybar-toggle"
    (lib.readFile ../../home-manager/common/scripts/hypr-waybar-toggle);
in
{

  touchGestures = true;

  programs.rofi = { extraConfig = { dpi = 0; }; };

  home.pointerCursor = { size = lib.mkForce 48; };

  home.packages = [
    pkgs.quickshell
    quickshellShell
  ];

  xdg.configFile = {
    "quickshell/shell/shell.qml".source = ../../../dotfiles/quickshell/shell/shell.qml;
    "quickshell/shell/Bar.qml".source = ../../../dotfiles/quickshell/shell/Bar.qml;
    "quickshell/shell/ScriptLabel.qml".source = ../../../dotfiles/quickshell/shell/ScriptLabel.qml;
    "quickshell/shell/ControlCenter.qml".source = ../../../dotfiles/quickshell/shell/ControlCenter.qml;
  };

  systemd.user.services.quickshell-shell = {
    Unit = {
      Description = "Quickshell desktop shell";
      After = [ "hyprland-session.target" ];
      PartOf = [ "hyprland-session.target" ];
    };
    Service = {
      ExecStartPre = "${waybarToggle}/bin/hypr-waybar-toggle off";
      ExecStart = "${pkgs.quickshell}/bin/quickshell -c shell";
      ExecStopPost = "${waybarToggle}/bin/hypr-waybar-toggle on";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "hyprland-session.target" ];
  };

}
