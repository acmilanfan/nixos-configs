{ pkgs, ... }: {

  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;

    # Whether to enable hyprland-session.target on hyprland startup
    systemd.enable = true;
    plugins = with pkgs; [
      hyprlandPlugins.hyprgrass
    ];
  };

  xdg.configFile = {
    "hypr/hyprland.conf".source = ./../../../dotfiles/hypr/hyprland.conf;
  };

  home.file = {
    ".config/waybar/config".source = ../../../dotfiles/waybar/config;
    ".config/waybar/style.css".source = ../../../dotfiles/waybar/style.css;
  };

  home.packages = with pkgs; [
    hyprland
    waybar
    dunst
    brightnessctl
    swaylock
    swww
    wl-clipboard
    grim
    slurp
    kanshi
  ];

}
