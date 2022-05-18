{ config, pkgs, lib, ... }: {

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "vanilla-dmz"
    "slack"
    "skypeforlinux"
    "sublimetext3"
    "idea-ultimate"
    "grammarly"
    "matte-black-violet-theme"
    "zoom"
    "reaper"
    "faac"
    "spotify"
    "bitwig-studio"
    "genymotion"
    "android-studio-stable"
    "teamviewer"
    "steam"
    "steam-original"
    "steam-runtime"
    "discord"
    "spotify-unwrapped"
    "obsidian"
    "electron"
  ];

  home.packages = with pkgs; [
    slack
    skypeforlinux
    sublime3
    zoom-us
    spotify
  ];
}
