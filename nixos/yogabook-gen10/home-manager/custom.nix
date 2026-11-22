{ pkgs, lib, ... }:
let
  quickshellPilot = pkgs.writeShellScriptBin "hypr-quickshell-pilot"
    (lib.readFile ../../home-manager/common/scripts/hypr-quickshell-pilot);
in
{

  touchGestures = true;

  programs.rofi = { extraConfig = { dpi = 0; }; };

  home.pointerCursor = { size = lib.mkForce 48; };

  home.packages = [
    pkgs.quickshell
    quickshellPilot
  ];

  xdg.configFile."quickshell/pilot/shell.qml".source =
    ../../../dotfiles/quickshell/pilot/shell.qml;

}
