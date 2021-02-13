{ config, pkgs, lib, ... }: {

  programs.sway = {
    enable = true;
    extraPackages = with pkgs; [
      swaylock
      swayidle
      swaybg
      xwayland
      mako
      light
      slurp
      grim
      wl-clipboard
      kitty
      imv
      libappindicator
      gammastep 
      (import (fetchTarball "channel:nixos-unstable") {}).swappy
      (import (fetchTarball "channel:nixos-unstable") {}).waybar
    ];
    extraSessionCommands = ''
      export SDL_VIDEODRIVER=wayland
      export _JAVA_AWT_WM_NONREPARENTING=1
    '';
    wrapperFeatures.gtk = true;
  };

  environment = {
    etc = {
      "sway/config".source = ./../../dotfiles/sway/config;
      "xdg/waybar/config".source = ./../../dotfiles/waybar/config;
      "xdg/waybar/style.css".source = ./../../dotfiles/waybar/style.css;
    };
  };
}
