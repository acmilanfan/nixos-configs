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
      wdisplays
      clipman
      wlogout
      cliphist
      nwg-drawer
      poweralertd
      kanshi
      #flameshot
      waybar
      #(import (fetchTarball "channel:nixos-unstable") {}).waybar
    ];
    extraSessionCommands = ''
      export SDL_VIDEODRIVER=wayland
      export _JAVA_AWT_WM_NONREPARENTING=1
    '';
    extraOptions = [ "--unsupported-gpu" ];
    wrapperFeatures.gtk = true;
  };

  environment = {
    etc = {
      "sway/config".source = ./../../dotfiles/sway/config;
      "sway/laptop_lid_check.sh".source = ./../../dotfiles/sway/laptop_lid_check.sh;
      "xdg/waybar/config".source = ./../../dotfiles/waybar/config;
      "xdg/waybar/style.css".source = ./../../dotfiles/waybar/style.css;
    };
  };

  systemd.packages = with pkgs.gnome; [ gdm gnome-session gnome-shell ];

  services.xserver = {
    displayManager.gdm.wayland = true;
    displayManager.sessionPackages = [ pkgs.sway ];
    libinput.enable = true;
  };
}
