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
    nixfmt-classic
    mpv
    audacious
    htop
    partition-manager
    pcmanfm
    konsole
    dolphin
    lf
    libreoffice
    yt-dlp
    google-chrome
    vial
    calibre
    davinci-resolve
    wineWow64Packages.stagingFull
    lutris
    winetricks
    jansson
    samba
  ];

}
