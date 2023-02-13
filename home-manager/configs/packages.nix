{ pkgs, ... }: {

  home.packages = with pkgs; [
    vimHugeX
    git
    arandr
    httpie
    pavucontrol
    playerctl
    kitty
    imv
    grim
    slurp
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
    lf
  ];

  programs.firefox.enable = true;
}
