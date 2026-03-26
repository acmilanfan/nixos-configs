{ config, pkgs, lib, ... }: {

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "vanilla-dmz"
    "slack"
    "idea-ultimate"
    "matte-black-violet-theme"
    "zoom"
    "faac"
    "genymotion"
    "discord"
    "electron"
  ];

  home.packages = with pkgs;
    lib.optionals pkgs.stdenv.isLinux [
      slack
      # zoom-us
    ];
}
