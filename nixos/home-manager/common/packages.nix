{ pkgs, ... }: {

  home.packages = with pkgs; [
    (writeShellScriptBin "screen-toggle" (lib.readFile ./scripts/screen-toggle))
    (writeShellScriptBin "touch-toggle" (lib.readFile ./scripts/touch-toggle))
    (writeShellScriptBin "try-lock" (lib.readFile ./scripts/try-lock))
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
    alsa-scarlett-gui
    btop
    qmk
    qmk-udev-rules
    protonvpn-gui
    thinkfan
    (python3.withPackages (ps: with ps; [ evdev ]))
    zenity
    onboard
  ];

}
