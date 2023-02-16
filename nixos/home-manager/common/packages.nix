{ pkgs, ... }: {

  home.packages = with pkgs; [
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
