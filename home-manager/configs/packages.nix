{ pkgs, ... }: {

  home.packages = with pkgs; [
    vimHugeX
    git
    arandr
    ranger
    httpie
    pavucontrol
    playerctl
    imv
    grim
    slurp
    kitty
    alacritty
    ranger
    networkmanagerapplet
    gnome3.polari
    chromium
    nixfmt
    mpv
    audacious
    htop
    partition-manager
    pcmanfm
    konsole
    dolphin
  ];

  programs.firefox.enable = true;
}
