{ config, pkgs, lib, ... }: {

  programs.sway = {
    enable = true;
    extraPackages = with pkgs; [
      swaylock
      swayidle
      swaybg
      xwayland
      waybar
      mako
      rofi
      light
      slurp
      grim
      wl-clipboard
      kitty
      imv
      rofi-pass
      (import (fetchTarball "channel:nixos-unstable") {}).redshift-wlr
      (import (fetchTarball "channel:nixos-unstable") {}).clipman
    ];
    extraSessionCommands = ''
      export SDL_VIDEODRIVER=wayland
      export _JAVA_AWT_WM_NONREPARENTING=1
    '';
  };

  environment = {
    etc = {
      "sway/config".source = ../../dotfiles/sway/config;
      "xdg/waybar/config".source = ../../dotfiles/waybar/config;
      "xdg/waybar/style.css".source = ../../dotfiles/waybar/style.css;
      "xdg//style.css".source = .../../dotfiles/waybar/style.css;
    };
  };
}
