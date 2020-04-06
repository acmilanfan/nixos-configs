{ config, pkgs, lib, ... }: {

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "vanilla-dmz"
    "slack"
    "skypeforlinux"
    "sublimetext3"
    "idea-ultimate"
  ];

  home.packages = with pkgs; [
    slack
    skypeforlinux
    sublime3
  ];
}
