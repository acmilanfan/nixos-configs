{
  pkgs,
  inputs,
  unstable,
  ...
}:

{
  ## TODO things to fix
  # - lock keybind
  # - try OmniWM instead of Aerospace
  # - top menu on mouse keybinds (menu and search separately, see OmniWM)
  # - kanata config for browser ctr/cmd for external keyboard
  # - add a keybind to switch kanata normal config and canata home row mode with numbers and modifiers disabled
  # - setup middle click three fingers tap
  # - when full screen a window (not OS fullscreen), automatically raise the window on top
  # - firenvim does not work
  # - warpd for system layer mouse replacement
  # - keyboard BT control
  # - fix sketchybar
  # - faster animations of window tiling
  # - remove window decoration on some (most) apps

  system.primaryUser = "andreishumailov";
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
    tree
    jq
    nixfmt-classic
    zsh
    bat
    httpie
    unstable.aerospace
  ];

  launchd.daemons.kanata = {
    command = "/opt/homebrew/bin/kanata --cfg /Users/andreishumailov/.config/kanata/active_config.kbd --port 5829";

    serviceConfig = {
      KeepAlive = {
        Crashed = true;
        SuccessfulExit = false;
      };
      RunAtLoad = true;
      StandardOutPath = "/Users/andreishumailov/.config/kanata/kanata.log";
      StandardErrorPath = "/Users/andreishumailov/.config/kanata/kanata.error.log";
      UserName = "root";
    };
  };

  launchd.agents.kanata-vk-agent = {
    command = "/opt/homebrew/bin/kanata-vk-agent -p 5829 -b com.apple.Safari,org.mozilla.firefox -i com.apple.keylayout.ABC";
    serviceConfig = {
      Label = "local.kanata-vk-agent";
      KeepAlive = {
        Crashed = true;
        SuccessfulExit = false;
      };
      RunAtLoad = true;
      StandardOutPath = "/tmp/kanata_vk_agent_stdout.log";
      StandardErrorPath = "/tmp/kanata_vk_agent_stderr.log";
    };
  };

  # launchd.agents.aerospace-window-highlight = {
  #   command = "/bin/zsh -c 'source /Users/andreishumailov/.zshrc && aerospace-highlight-daemon'";
  #   serviceConfig = {
  #     Label = "local.aerospace-window-highlight";
  #     KeepAlive = {
  #       Crashed = true;
  #       SuccessfulExit = false;
  #     };
  #     RunAtLoad = true;
  #     StandardOutPath = "/tmp/aerospace_window_highlight_stdout.log";
  #     StandardErrorPath = "/tmp/aerospace_window_highlight_stderr.log";
  #     # Wait a bit after system startup to ensure Aerospace is running
  #     StartInterval = 30;
  #   };
  # };

  # launchd.agents.scroll-reverser = {
  #   command =
  #     "open -a /Applications/Scroll Reverser.app/Contents/MacOS/Scroll Reverser";
  #   serviceConfig = {
  #     KeepAlive = {
  #       Crashed = true;
  #       SuccessfulExit = false;
  #     };
  #     RunAtLoad = true;
  #   };
  # };

  # Homebrew packages that don't work well with nix-darwin
  homebrew = {
    enable = true;
    # global.autoUpdate = true;
    global.autoUpdate = false;
    onActivation = {
      cleanup = "zap";
      # autoUpdate = true;
      autoUpdate = false;
      # upgrade = true;
      upgrade = false;
    };

    # Homebrew casks (GUI applications)
    casks = [
      # Browsers
      "google-chrome"
      "firefox"

      # Development
      # "visual-studio-code"
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
      "raycast"
      "syncthing-app"
      "karabiner-elements"
      "cleanupbuddy"
      "nextcloud"

      # Terminal
      "kitty"
      "alacritty"

      # Usability improvements
      "dimentium/autoraise/autoraiseapp"
      "scroll-reverser"
      "hammerspoon"
      "balenaetcher"
      "omniwm"
      "middleclick"
    ];

    # Homebrew formulae (CLI tools)
    brews = [
      # Tools that work better via homebrew
      "mas" # Mac App Store CLI
      "scrcpy" # Android screen mirroring
      "kanata"
      "firefoxpwa"
      "devsunb/tap/kanata-vk-agent"
      "docker" # Docker CLI (works with colima)
      "docker-compose" # Docker Compose
    ];

    # Homebrew taps
    taps = [
      "FelixKratz/formulae"
      "dimentium/autoraise"
      "devsunb/tap"
      "BarutSRB/tap"
    ];

    # Mac App Store apps
    masApps = {
      # "Weekenduo" = 6757489903;
      # "Xcode" = 497799835;
      # "TestFlight" = 899247664;
    };
  };

  # Fonts
  fonts.packages = with pkgs; [
    # Core fonts matching NixOS configuration
    roboto
    roboto-mono
    roboto-slab
    roboto-serif
    ubuntu-classic
    nerd-fonts.roboto-mono
    jetbrains-mono
    font-awesome
    noto-fonts
    inter
    fira-code
    fira-code-symbols
    nerd-fonts.jetbrains-mono
  ];

  # Nix package manager settings
  nix = {
    enable = true;
    package = pkgs.nix;
    optimise.automatic = true;
    settings = {
      # Enable flakes and new command-line interface
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      # Trusted users for multi-user nix
      trusted-users = [
        "root"
        "andreishumailov"
      ];
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

    # Setup firefoxpwa
    echo "Linking firefoxpwa native messaging host..."
    mkdir -p "/Library/Application Support/Mozilla/NativeMessagingHosts"
    ln -sf "/opt/homebrew/opt/firefoxpwa/share/firefoxpwa.json" "/Library/Application Support/Mozilla/NativeMessagingHosts/firefoxpwa.json"

     # Setup Scroll Reverser
    echo "Setting up Scroll Reverser"
    defaults write com.pilotmoon.scroll-reverser reverseTrackpad -bool true
    defaults write com.pilotmoon.scroll-reverser reverseMouse -bool false
    killall "Scroll Reverser" || true
    open -a "Scroll Reverser"
  '';

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
    # Custom system preferences using defaults
    CustomUserPreferences = {
      "com.apple.symbolichotkeys" = {
        AppleSymbolicHotKeys = {
          # Disable '^ + Space' for selecting the previous input source
          "60" = {
            enabled = false;
          };
          # Disable '^ + Option + Space' for selecting the next input source
          "61" = {
            enabled = false;
          };
          # Disable 'Cmd + Space' for Spotlight Search
          "64" = {
            enabled = false;
            # value = {
            #   parameters = [
            #     100
            #     2
            #     524288
            #   ]; # 'd' key (100), virtual key (2), Alt modifier (524288)
            #   type = "standard";
            # };
          };
          # Enable 'Cmd + Alt + Space' for Finder search window
          "65" = {
            enabled = true;
          };
        };
      };

    };

    # Dock settings
    dock = {
      autohide = true;
      autohide-delay = 0.0;
      autohide-time-modifier = 0.2;
      orientation = "left";
      show-recents = false;
      static-only = true;
      tilesize = 48;
      expose-group-apps = true;
    };

    spaces = {
      spans-displays = true;
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
      "com.apple.swipescrolldirection" = false; # true = natural scrolling
      # Appearance
      AppleInterfaceStyle = "Dark";
      AppleInterfaceStyleSwitchesAutomatically = false;

      # Hide menu bar (for SketchyBar)
      _HIHideMenuBar = true;

      # Window appearance settings to minimize decorations
      # AppleReduceDesktopTinting = true;

      # Allow windows drag by any part
      NSWindowShouldDragOnGesture = true;
      NSAutomaticWindowAnimationsEnabled = false;

      # Minimize window decorations
      AppleShowScrollBars = "WhenScrolling";
      NSWindowResizeTime = 1.0e-3;

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

    # defaults write com.pilotmoon.scroll-reverser reverseTrackpad -bool true
    # defaults write com.pilotmoon.scroll-reverser reverseMouse -bool false
    # Trackpad settings
    trackpad = {
      Clicking = true;
      Dragging = true;
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = true;
    };

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
      # {
      #   HIDKeyboardModifierMappingSrc = 30064771296; # Left Control
      #   HIDKeyboardModifierMappingDst = 30064771299; # Left Command
      # }
      # {
      #   HIDKeyboardModifierMappingSrc = 30064771299; # Left Command
      #   HIDKeyboardModifierMappingDst = 30064771296; # Left Control
      # }

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
  security.pam.services.sudo_local.touchIdAuth = true;
  security.pam.services.sudo_local.reattach = true;
}
