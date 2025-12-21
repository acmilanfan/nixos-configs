{ pkgs, ... }: {

  home.packages = with pkgs;
    [
      git
      httpie
      kitty
      nixfmt-classic
      htop
      yt-dlp
      clinfo
      jq
      scrcpy
      pandoc
      btop
      qmk
      bat
    ] ++ lib.optionals pkgs.stdenv.isLinux [
      (writeShellScriptBin "screen-toggle"
        (lib.readFile ./scripts/screen-toggle))
      (writeShellScriptBin "hypr-profile"
        (lib.readFile ./scripts/hypr-profile))
      (writeShellScriptBin "hypr-send-to-other-monitor"
        (lib.readFile ./scripts/hypr-send-to-other-monitor))
      (writeShellScriptBin "hypr-focus-other-monitor"
        (lib.readFile ./scripts/hypr-focus-other-monitor))
      (writeShellScriptBin "hypr-cycle-layout"
        (lib.readFile ./scripts/hypr-cycle-layout))
      (writeShellScriptBin "touch-toggle" (lib.readFile ./scripts/touch-toggle))
      (writeShellScriptBin "try-lock" (lib.readFile ./scripts/try-lock))
      vial
      (python3.withPackages (ps: with ps; [ evdev ]))
      qmk-udev-rules
      vlc
      lutris
      google-chrome
      alsa-scarlett-gui
      android-tools
      mpv
      audacious
      calibre
      libreoffice
      pcmanfm
      arandr
      kdePackages.partitionmanager
      kdePackages.konsole
      kdePackages.dolphin
      networkmanagerapplet
      imv
      grim
      slurp
      playerctl
      pavucontrol
      wineWowPackages.full
      winetricks
      thinkfan
      lm_sensors
      thinkfan
      protonvpn-gui
      zenity
      onboard
      # TODO move Linux specific stuff
      # ...
    ] ++ lib.optionals pkgs.stdenv.isDarwin [

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
