{ pkgs, lib, ... }: {

  home.username = "andreishumailov";
  home.homeDirectory = lib.mkForce "/Users/andreishumailov";

  imports = [
    # Import common configurations with macOS guards
    ../home-manager/common/default.nix
    ./git.nix
  ];

  # macOS-specific packages
  home.packages = with pkgs;
    [
      # macOS-specific utilities
      mas # Mac App Store CLI
      m-cli # Swiss Army Knife for macOS

      # Development tools that work well on macOS
      colima # Container runtime for macOS

      # Additional macOS tools
      duti # Default application handler

      # Window management
      sketchybar # Status bar
    ] ++ lib.optionals pkgs.stdenv.isDarwin [
      # Darwin-specific packages
    ];

  # macOS-specific shell aliases
  programs.zsh.shellAliases = pkgs.lib.mkMerge [{
    # macOS-specific aliases
    sup = "darwin-rebuild switch --flake $HOME/configs/nixos-configs/#mac-work";
    hup =
      "home-manager switch --flake $HOME/configs/nixos-configs/#andreishumailov@work";

    # macOS system management
    flush-dns =
      "sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder";
    show-hidden =
      "defaults write com.apple.finder AppleShowAllFiles -bool true && killall Finder";
    hide-hidden =
      "defaults write com.apple.finder AppleShowAllFiles -bool false && killall Finder";

    # Docker/Colima shortcuts
    docker-start = "colima start";
    docker-stop = "colima stop";

    # AeroSpace shortcuts
    aerospace-reload = "aerospace reload-config";
    aerospace-list = "aerospace list-windows --all";
    aerospace-debug = "aerospace debug-windows";

    aerospace-highlight = "~/.config/aerospace/window-highlight.sh start";
    aerospace-highlight-stop = "~/.config/aerospace/window-highlight.sh stop";
    aerospace-highlight-toggle =
      "~/.config/aerospace/window-highlight.sh toggle";
    aerospace-highlight-status =
      "~/.config/aerospace/window-highlight.sh status";
    aerospace-highlight-daemon = "~/.config/aerospace/window-highlight-daemon.sh start";
    aerospace-highlight-daemon-stop = "~/.config/aerospace/window-highlight-daemon.sh stop";
    aerospace-highlight-daemon-status = "~/.config/aerospace/window-highlight-daemon.sh status";

    # Clipboard shortcuts
    clipboard-history = "open -a Maccy";
    clipboard-clear = "defaults delete org.p0deje.Maccy";

      # Kanata configuration management
      reload-kanata = "~/.config/kanata/reload-kanata.sh";
      reload-kanata-logs = "~/.config/kanata/reload-kanata.sh --show-logs";

    # Hybrid keyboard management (Kanata + Karabiner)
    # kanata-start = "~/.config/kanata/kanata-launcher.sh start";
    # kanata-stop = "~/.config/kanata/kanata-launcher.sh stop";
    # kanata-restart = "~/.config/kanata/kanata-launcher.sh restart";
    # kanata-status = "~/.config/kanata/kanata-launcher.sh status";
    # kanata-log = "~/.config/kanata/kanata-launcher.sh log";
    # kanata-test = "~/.config/kanata/kanata-launcher.sh test";

  }];

  # macOS-specific programs configuration
  programs.git = {
    extraConfig = {
      # macOS-specific git settings
      credential.helper = "osxkeychain";
    };
  };

  # macOS-specific home files
  home.file = {
    # macOS-specific dotfiles can go here
    ".hushlogin".text = ""; # Suppress login message

    # AeroSpace configuration
    ".config/aerospace/aerospace.toml".source =
      ../../dotfiles/aerospace/aerospace.toml;
    ".config/aerospace/window-highlight.sh".source =
      ../../dotfiles/aerospace/window-highlight.sh;
    ".config/aerospace/window-highlight-daemon.sh".source =
      ../../dotfiles/aerospace/window-highlight-daemon.sh;
    # JankyBorders configuration
    ".config/borders/bordersrc".source = ../../dotfiles/jankyborders/bordersrc;

    # SketchyBar configuration
    ".config/sketchybar/sketchybarrc".source =
      ../../dotfiles/sketchybar/sketchybarrc;
    ".config/sketchybar/colors.sh".source = ../../dotfiles/sketchybar/colors.sh;
    ".config/sketchybar/icons.sh".source = ../../dotfiles/sketchybar/icons.sh;
    ".config/sketchybar/items/spaces.sh".source =
      ../../dotfiles/sketchybar/items/spaces.sh;
    ".config/sketchybar/items/front_app.sh".source =
      ../../dotfiles/sketchybar/items/front_app.sh;
    ".config/sketchybar/items/calendar.sh".source =
      ../../dotfiles/sketchybar/items/calendar.sh;
    ".config/sketchybar/items/volume.sh".source =
      ../../dotfiles/sketchybar/items/volume.sh;
    ".config/sketchybar/items/battery.sh".source =
      ../../dotfiles/sketchybar/items/battery.sh;
    ".config/sketchybar/items/cpu.sh".source =
      ../../dotfiles/sketchybar/items/cpu.sh;
    ".config/sketchybar/items/memory.sh".source =
      ../../dotfiles/sketchybar/items/memory.sh;
    ".config/sketchybar/items/network.sh".source =
      ../../dotfiles/sketchybar/items/network.sh;
    ".config/sketchybar/items/aerospace.sh".source =
      ../../dotfiles/sketchybar/items/aerospace.sh;
    ".config/sketchybar/items/media.sh".source =
      ../../dotfiles/sketchybar/items/media.sh;
    ".config/sketchybar/plugins/space.sh".source =
      ../../dotfiles/sketchybar/plugins/space.sh;
    ".config/sketchybar/plugins/space_windows.sh".source =
      ../../dotfiles/sketchybar/plugins/space_windows.sh;
    ".config/sketchybar/plugins/front_app.sh".source =
      ../../dotfiles/sketchybar/plugins/front_app.sh;
    ".config/sketchybar/plugins/calendar.sh".source =
      ../../dotfiles/sketchybar/plugins/calendar.sh;
    ".config/sketchybar/plugins/volume.sh".source =
      ../../dotfiles/sketchybar/plugins/volume.sh;
    ".config/sketchybar/plugins/battery.sh".source =
      ../../dotfiles/sketchybar/plugins/battery.sh;
    ".config/sketchybar/plugins/cpu.sh".source =
      ../../dotfiles/sketchybar/plugins/cpu.sh;
    ".config/sketchybar/plugins/memory.sh".source =
      ../../dotfiles/sketchybar/plugins/memory.sh;
    ".config/sketchybar/plugins/network.sh".source =
      ../../dotfiles/sketchybar/plugins/network.sh;
    ".config/sketchybar/plugins/aerospace.sh".source =
      ../../dotfiles/sketchybar/plugins/aerospace.sh;
    ".config/sketchybar/plugins/media.sh".source =
      ../../dotfiles/sketchybar/plugins/media.sh;
    ".config/sketchybar/plugins/icon_map.sh".source =
      ../../dotfiles/sketchybar/plugins/icon_map.sh;

    # Maccy configuration
    ".config/maccy/maccy-config.sh".source =
      ../../dotfiles/maccy/maccy-config.sh;

    # Karabiner-Elements configuration
    ".config/karabiner/karabiner.json".source =
      ../../dotfiles/karabiner/karabiner.json;

    # Kanata configuration (home row mods only)
    ".config/kanata/kanata.kbd".source = ../../dotfiles/kanata/kanata.kbd;
    ".config/kanata/reload-kanata.sh".source = ../../dotfiles/kanata/reload-kanata.sh;
  };

  # macOS-specific environment variables
  home.sessionVariables = {
    # macOS-specific environment
    BROWSER = "open";
  };

  home.stateVersion = "25.05";
}
