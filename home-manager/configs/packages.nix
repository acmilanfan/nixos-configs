{ pkgs, ... }: {

  home.packages = with pkgs; [
    vimHugeX
    git
    arandr
    ranger
    httpie
    jetbrains.jdk
    pavucontrol
    playerctl
    imv
    rofi-pass
    grim
    slurp
    kitty
    ranger
    networkmanagerapplet
    gnome3.polari
    chromium
    nixfmt
    #safeeyes
    mpv
    audacious
    htop
    partition-manager
  ];

  programs.firefox.enable = true;
}
