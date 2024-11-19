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
    clinfo
    lutris
    jq
    wineWowPackages.full
    winetricks
    thinkfan
    lm_sensors
    vlc
    scrcpy
    android-tools
    pandoc
  ];

}
