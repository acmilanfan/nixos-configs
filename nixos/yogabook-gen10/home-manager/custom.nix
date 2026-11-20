{ pkgs, lib, ... }: {

  touchGestures = true;

  programs.rofi = { extraConfig = { dpi = 0; }; };

  home.pointerCursor = { size = lib.mkForce 48; };

}
