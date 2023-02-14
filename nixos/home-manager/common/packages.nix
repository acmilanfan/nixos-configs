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

}
