{ config, pkgs, inputs, ... }:

{
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages = with pkgs; [
    # Core system utilities
    vim
    git
    curl
    wget
    htop
    tree
    jq

    # Development tools
    nixfmt-classic

    # Terminal and shell
    zsh

    # File management
    bat

    # Network tools
    httpie
  ];

  # Homebrew packages that don't work well with nix-darwin
  homebrew = {
    enable = true;

    # Homebrew casks (GUI applications)
    casks = [
      # Browsers
      "google-chrome"
      "firefox"

      # Development
      # "visual-studio-code"
      "docker"
      # "postman"

      # Communication
      "slack"
      # "discord"
      # "zoom"

      # Productivity
      # "notion"
      # "obsidian"

      # Media
      # "vlc"
      # "spotify"

      # Utilities
      # "alfred"
      # "rectangle"
      # "the-unarchiver"
      # "appcleaner"
      # "raycast"

      # Terminal
      "kitty"
      "alacritty"
    ];

    # Homebrew formulae (CLI tools)
    brews = [
      # Tools that work better via homebrew
      "mas" # Mac App Store CLI
      "scrcpy" # Android screen mirroring
    ];

    # Mac App Store apps
    masApps = {
      "Xcode" = 497799835;
      "TestFlight" = 899247664;
    };

    # Cleanup options
    onActivation = {
      cleanup = "zap";
      autoUpdate = true;
      upgrade = true;
    };
  };

  # Fonts
  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "FiraCode" "DroidSansMono" "JetBrainsMono" ]; })
    fira-code
    fira-code-symbols
  ];

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;

  # Nix package manager settings
  nix = {
    package = pkgs.nix;
    settings = {
      # Enable flakes and new command-line interface
      experimental-features = [ "nix-command" "flakes" ];

      # Optimize storage
      auto-optimise-store = true;

      # Trusted users for multi-user nix
      trusted-users = [ "root" "andreishumailov" ];
    };

    # Garbage collection
    gc = {
      automatic = true;
      interval = { Weekday = 0; Hour = 2; Minute = 0; };
      options = "--delete-older-than 30d";
    };
  };

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true;

  # Set Git commit hash for darwin-version.
  system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 5;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # System preferences
  system.defaults = {
    # Dock settings
    dock = {
      autohide = true;
      autohide-delay = 0.0;
      autohide-time-modifier = 0.2;
      orientation = "bottom";
      show-recents = false;
      static-only = true;
      tilesize = 48;
    };

    # Finder settings
    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
      CreateDesktop = false;
      FXDefaultSearchScope = "SCcf"; # Search current folder
      FXEnableExtensionChangeWarning = false;
      FXPreferredViewStyle = "Nlsv"; # List view
      QuitMenuItem = true;
      ShowPathbar = true;
      ShowStatusBar = true;
    };

    # Login window settings
    loginwindow = {
      GuestEnabled = false;
      SHOWFULLNAME = false;
    };

    # Menu bar settings
    menuExtrasClock = {
      Show24Hour = true;
      ShowAMPM = false;
      ShowDate = 1;
      ShowDayOfMonth = true;
      ShowDayOfWeek = true;
      ShowSeconds = false;
    };

    # NSGlobalDomain settings (system-wide preferences)
    NSGlobalDomain = {
      # Appearance
      AppleInterfaceStyle = "Dark";
      AppleInterfaceStyleSwitchesAutomatically = false;

      # Keyboard
      ApplePressAndHoldEnabled = false;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;

      # Mouse/Trackpad
      AppleEnableMouseSwipeNavigateWithScrolls = true;
      AppleEnableSwipeNavigateWithScrolls = true;

      # Misc
      AppleShowAllExtensions = true;
      AppleShowScrollBars = "Always";
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
      PMPrintingExpandedStateForPrint = true;
      PMPrintingExpandedStateForPrint2 = true;
    };

    # Trackpad settings
    trackpad = {
      Clicking = true;
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = true;
    };

    # Universal Access
    universalaccess = {
      reduceMotion = true;
    };
  };

  # Keyboard settings
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToEscape = true;
  };

  # Security settings
  security.pam.enableSudoTouchId = true;
}
