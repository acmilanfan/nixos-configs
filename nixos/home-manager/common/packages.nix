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
    kdePackages.partitionmanager
    pcmanfm
    kdePackages.konsole
    kdePackages.dolphin
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
    bat
  ];

  # TODO move
  programs.lf = {
    enable = true;
    previewer.source = pkgs.writeShellScript "bat-preview" ''
      #!/bin/sh
      file="$1"
      [ -d "$file" ] && exit 1
      bat --theme=nightfox --style=plain --color=always "$file"
    '';
    settings = { preview = true; };
  };

  home.file = {
    ".config/bat/themes/nightfox.tmTheme".source = pkgs.fetchurl {
      url =
        "https://raw.githubusercontent.com/EdenEast/nightfox.nvim/main/extra/nightfox/nightfox.tmTheme";
      sha256 = "sha256-J/0baDEYrV7on7qeHa4dIvLHPY4CH0lVLj4IR2G0pNs= ";
    };

    ".config/bat/config".text = ''
      --theme=nightfox
    '';
  };

}
