{ pkgs, ... }: {

  home.packages = with pkgs; [
    vimHugeX
    pass
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
  ];

  programs.firefox.enable = true;
}
