{ pkgs, lib, ... }: {

  programs.rofi = { extraConfig = { dpi = 0; }; };

  home.pointerCursor = { size = lib.mkForce 32; };

  # home.packages = with pkgs; [ (callPackage ./vantage.nix { }) ];

  # home.file.".config/REAPER/reaper.ini".text = ''
  #   [.swell]
  #   ui_scale=1.7 // scales the sizes in libSwell.colortheme
  # '';

}
