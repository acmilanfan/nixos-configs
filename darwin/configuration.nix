{ config, pkgs, inputs, ... }:

{
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget

  ## TODO things to fix
  # - proper full screen
  # - focus follow mouse
  # - highlight current winodow if tiled more than two
  # - fix sketchybar to show only workspaces with windows opened
  # - all apps losing focus after maccy call
  # - remove window decoration on some (most) apps
  # - some windows do not tile properly
  # - keyboard BT control
  # - touchpad tap functionality
  # - setup middle click three fingers tap
  # - faster animations of window tiling
  # - lock keybind
  # - maccy clipboard control with vim ctrl+keys
  # - syncthing for orgmode folder
  # - aerospace keybind to sycle through windows instead of
  # - fixed accordion mode on one specific screen
  # -

  system.primaryUser = "andreishumailov";
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

    # Window management
    aerospace
    sketchybar
  ];

  # Homebrew packages that don't work well with nix-darwin
  homebrew = {
    enable = true;

    # Homebrew casks (GUI applications)
    casks = [
      # Browsers
      "google-chrome"
      # "firefox"

      # Development
      # "visual-studio-code"
      # "docker"
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
      "maccy" # Clipboard history manager

      # Terminal
      "kitty"
      "alacritty"
    ];

    # Homebrew formulae (CLI tools)
    brews = [
      # Tools that work better via homebrew
      "mas" # Mac App Store CLI
      "scrcpy" # Android screen mirroring
      "borders" # JankyBorders for window highlighting (from FelixKratz tap)
    ];

    # Homebrew taps
    taps = [
      "FelixKratz/formulae"
    ];

    # Mac App Store apps
    masApps = {
      # "Xcode" = 497799835;
      # "TestFlight" = 899247664;
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
    # Core fonts matching NixOS configuration
    roboto
    roboto-mono
    roboto-slab
    roboto-serif
    ubuntu_font_family
    nerd-fonts.roboto-mono
    jetbrains-mono
    font-awesome
    noto-fonts
    inter
    fira-code
    fira-code-symbols
  ];

  # Nix package manager settings
  nix = {
    enable = true;
    package = pkgs.nix;
    optimise.automatic = true;
    settings = {
      # Enable flakes and new command-line interface
      experimental-features = [ "nix-command" "flakes" ];

      # Trusted users for multi-user nix
      trusted-users = [ "root" "andreishumailov" ];
    };

    # Garbage collection
    gc = {
      automatic = true;
      interval = {
        Weekday = 0;
        Hour = 2;
        Minute = 0;
      };
      options = "--delete-older-than 30d";
    };
  };

  system.activationScripts.postActivation.text = ''
    # Following line should allow us to avoid a logout/login cycle when changing settings
    sudo -u andreishumailov /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  '';

  # Create /etc/zshrc that loads the nix-darwin environment.
  programs.zsh.enable = true;

  # Set Git commit hash for darwin-version.
  system.configurationRevision =
    inputs.self.rev or inputs.self.dirtyRev or null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 5;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # System preferences
  system.defaults = {
    # Custom system preferences using defaults
    CustomUserPreferences = {
      "com.apple.symbolichotkeys" = {
        AppleSymbolicHotKeys = {
          # Disable '^ + Space' for selecting the previous input source
          "60" = { enabled = false; };
          # Disable '^ + Option + Space' for selecting the next input source
          "61" = { enabled = false; };
          # Disable 'Cmd + Space' for Spotlight Search
          "64" = {
            enabled = true;
            value = {
              parameters = [
                100
                2
                524288
              ]; # 'd' key (100), virtual key (2), Alt modifier (524288)
              type = "standard";
            };
          };
          # Disable 'Cmd + Alt + Space' for Finder search window
          "65" = { enabled = false; };
        };
      };
    };

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
    #
    #    # Finder settings
    #    finder = {
    #      AppleShowAllExtensions = true;
    #      AppleShowAllFiles = true;
    #      CreateDesktop = false;
    #      FXDefaultSearchScope = "SCcf"; # Search current folder
    #      FXEnableExtensionChangeWarning = false;
    #      FXPreferredViewStyle = "Nlsv"; # List view
    #      QuitMenuItem = true;
    #      ShowPathbar = true;
    #      ShowStatusBar = true;
    #    };
    #
    #    # Login window settings
    #    loginwindow = {
    #      GuestEnabled = false;
    #      SHOWFULLNAME = false;
    #    };

    # Menu bar settings
    #    menuExtrasClock = {
    #      Show24Hour = true;
    #      ShowAMPM = false;
    #      ShowDate = 1;
    #      ShowDayOfMonth = true;
    #      ShowDayOfWeek = true;
    #      ShowSeconds = false;
    #    };

    # NSGlobalDomain settings (system-wide preferences)
    NSGlobalDomain = {
      #      # Appearance
      AppleInterfaceStyle = "Dark";
      AppleInterfaceStyleSwitchesAutomatically = false;

      # Hide menu bar (for SketchyBar)
      _HIHideMenuBar = true;

      # Window appearance settings to minimize decorations
      # AppleReduceDesktopTinting = true;

      # Minimize window decorations
      AppleShowScrollBars = "WhenScrolling";
      NSWindowResizeTime = 0.001;

      # Reduce visual effects that add to window decorations
      NSUseAnimatedFocusRing = false;

      #      # Keyboard
      ApplePressAndHoldEnabled = false;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      #
      #      # Mouse/Trackpad
      #      AppleEnableMouseSwipeNavigateWithScrolls = true;
      #      AppleEnableSwipeNavigateWithScrolls = true;
      #
      #      # Misc
      #      AppleShowAllExtensions = true;
      #      AppleShowScrollBars = "Always";
      #      NSAutomaticCapitalizationEnabled = false;
      #      NSAutomaticDashSubstitutionEnabled = false;
      #      NSAutomaticPeriodSubstitutionEnabled = false;
      #      NSAutomaticQuoteSubstitutionEnabled = false;
      #      NSAutomaticSpellingCorrectionEnabled = false;
      #      NSNavPanelExpandedStateForSaveMode = true;
      #      NSNavPanelExpandedStateForSaveMode2 = true;
      #      PMPrintingExpandedStateForPrint = true;
      #      PMPrintingExpandedStateForPrint2 = true;
    };

    # Trackpad settings
    #    trackpad = {
    #      Clicking = true;
    #      TrackpadRightClick = true;
    #      TrackpadThreeFingerDrag = true;
    #    };

    # Universal Access
    #    universalaccess = {
    #      reduceMotion = true;
    #    };
  };

  # Keyboard settings
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToEscape = true;
    userKeyMapping = [
      # Left Control ↔ Left Command
      {
        HIDKeyboardModifierMappingSrc = 30064771296; # Left Control
        HIDKeyboardModifierMappingDst = 30064771299; # Left Command
      }
      {
        HIDKeyboardModifierMappingSrc = 30064771299; # Left Command
        HIDKeyboardModifierMappingDst = 30064771296; # Left Control
      }

      # # Right Control ↔ Right Command
      # {
      #   HIDKeyboardModifierMappingSrc = 30064771300; # Right Control
      #   HIDKeyboardModifierMappingDst = 30064771303; # Right Command
      # }
      # {
      #   HIDKeyboardModifierMappingSrc = 30064771303; # Right Command
      #   HIDKeyboardModifierMappingDst = 30064771300; # Right Control
      # }
    ];
    # swapLeftCommandAndLeftAlt = true;
  };

  # Security settings
  # security.pam.enableSudoTouchId = true;
}
