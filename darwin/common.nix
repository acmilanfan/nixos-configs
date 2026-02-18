{
  pkgs,
  inputs,
  unstable,
  config,
  ...
}:

let
  user = config.system.primaryUser;

  # Dedicated startup script for GUI apps and driver initialization
  startupScript = pkgs.writeShellScriptBin "darwin-startup" ''
    USER_HOME="/Users/${user}"
    export PATH=$PATH:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin

    echo "--- Darwin Startup Script ($(date)) ---"

    # 1. Karabiner-Elements Driver Loader
    # We open it to ensure drivers are active, then clean up the GUI components
    if [ -d "/Applications/Karabiner-Elements.app" ]; then
      echo "Initializing Karabiner-Elements drivers..."
      open -a "Karabiner-Elements"
      sleep 1

      echo "Cleaning up Karabiner GUI components..."
      # Use multiple methods to ensure it's gone from tray
      osascript -e 'quit app "Karabiner-Elements"' 2>/dev/null || true
      pkill -x "Karabiner-Menu" 2>/dev/null || true
      pkill -x "Karabiner-NotificationWindow" 2>/dev/null || true
      pkill -x "Karabiner-NotificationCenter" 2>/dev/null || true
      pkill -x "karabiner_console_user_server" 2>/dev/null || true
    fi

    # 2. Start GUI Utilities
    # 3. Ensure apps are running
    # We only start these apps if they are NOT currently running.
    # This prevents flickering and state loss during rebuilds.
    ensure_apps=(
      "Hammerspoon"
      "Raycast"
      "Scroll Reverser"
      "MiddleClick"
      "AutoRaise"
    )

    for app in "''${ensure_apps[@]}"; do
      if ! pgrep -x "$app" >/dev/null; then
        if [ -d "/Applications/$app.app" ] || [ -d "$USER_HOME/Applications/$app.app" ]; then
          echo "Starting $app (was not running)..."

          # If we are starting Hammerspoon, we might want a clean sketchybar
          if [ "$app" == "Hammerspoon" ]; then
             pkill -x "sketchybar" 2>/dev/null || true
          fi

          open -a "$app"
        fi
      fi
    done

    # 4. Cursorcerer
    CURSORCERER_SYS="/Library/PreferencePanes/Cursorcerer.prefPane/Contents/Resources/Cursorcerer.app"
    CURSORCERER_USER="$USER_HOME/Library/PreferencePanes/Cursorcerer.prefPane/Contents/Resources/Cursorcerer.app"
    if [ -d "$CURSORCERER_SYS" ]; then
      echo "Starting Cursorcerer (System)..."
      open -a "$CURSORCERER_SYS"
    elif [ -d "$CURSORCERER_USER" ]; then
      echo "Starting Cursorcerer (User)..."
      open -a "$CURSORCERER_USER"
    fi

    echo "Startup script completed."
  '';
in
{
  ## TODO things to fix
  # - kanata config for browser ctr/cmd for external keyboard
  # - firenvim does not work
  # - warpd for system layer mouse replacement
  # - keyboard BT control

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
    startupScript
  ];

  launchd.agents.kanata = {
    command = "/usr/bin/sudo /opt/homebrew/bin/kanata --cfg /Users/${user}/.config/kanata/active_config.kbd --port 5829";

    serviceConfig = {
      Label = "local.kanata";
      KeepAlive = {
        Crashed = true;
        SuccessfulExit = false;
      };
      RunAtLoad = true;
      ProcessType = "Interactive";
      StandardOutPath = "/tmp/kanata.log";
      StandardErrorPath = "/tmp/kanata.error.log";
    };
  };

  launchd.agents.kanata-charibdis = {
    command = "/usr/bin/sudo /opt/homebrew/bin/kanata --cfg /Users/${user}/.config/kanata/kanata-charibdis-browser.kbd --port 5830";

    serviceConfig = {
      Label = "local.kanata-charibdis";
      KeepAlive = {
        Crashed = true;
        SuccessfulExit = false;
      };
      RunAtLoad = true;
      ProcessType = "Interactive";
      StandardOutPath = "/tmp/kanata-charibdis.log";
      StandardErrorPath = "/tmp/kanata-charibdis.error.log";
    };
  };

  security.sudo.extraConfig = ''
    %admin ALL=(ALL) NOPASSWD: /opt/homebrew/bin/kanata
  '';

  launchd.agents.kanata-vk-agent = {
    command = "/bin/bash -c 'sleep 5; exec /opt/homebrew/bin/kanata-vk-agent -p 5829 -b com.apple.Safari,org.mozilla.firefox,com.google.Chrome,arc.browser -i com.apple.keylayout.ABC'";
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

  launchd.agents.kanata-vk-agent-charibdis = {
    command = "/bin/bash -c 'sleep 5; exec /opt/homebrew/bin/kanata-vk-agent -p 5830 -b com.apple.Safari,org.mozilla.firefox,com.google.Chrome,arc.browser -i com.apple.keylayout.ABC'";
    serviceConfig = {
      Label = "local.kanata-vk-agent-charibdis";
      KeepAlive = {
        Crashed = true;
        SuccessfulExit = false;
      };
      RunAtLoad = true;
      StandardOutPath = "/tmp/kanata_vk_agent_charibdis_stdout.log";
      StandardErrorPath = "/tmp/kanata_vk_agent_charibdis_stderr.log";
    };
  };

  # Main login agent that triggers the startup script
  launchd.agents.darwin-startup = {
    command = "${startupScript}/bin/darwin-startup";
    serviceConfig = {
      Label = "local.darwin-startup";
      RunAtLoad = true;
      LaunchOnlyOnce = true;
      StandardOutPath = "/tmp/darwin-startup.log";
      StandardErrorPath = "/tmp/darwin-startup.err.log";
    };
  };

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
      "middleclick"
      "cursorcerer"
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
        "${user}"
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
    # Setup Kanata configuration
    echo "Setting up Kanata configuration..."
    mkdir -p "/Users/${user}/.config/kanata"
    if [ ! -L "/Users/${user}/.config/kanata/active_config.kbd" ] && [ ! -f "/Users/${user}/.config/kanata/active_config.kbd" ]; then
      echo "Initializing active_config.kbd symlink..."
      ln -sf "/Users/${user}/.config/kanata/kanata-homerow.kbd" "/Users/${user}/.config/kanata/active_config.kbd"
    fi
    chown -R ${user}:staff "/Users/${user}/.config/kanata"

    # Setup firefoxpwa
    echo "Linking firefoxpwa native messaging host..."
    mkdir -p "/Library/Application Support/Mozilla/NativeMessagingHosts"
    ln -sf "/opt/homebrew/opt/firefoxpwa/share/firefoxpwa.json" "/Library/Application Support/Mozilla/NativeMessagingHosts/firefoxpwa.json"

    # Setup firenvim native messaging host
    echo "Setting up firenvim native messaging host..."
    sudo -u ${user} nvim --headless "+call firenvim#install(0)" +quit 2>/dev/null || true

    # Run user-level startup tasks (apps, drivers)
    # We use kickstart to run the agent in the proper GUI session context
    echo "Triggering user-level startup script via launchd..."
    USER_ID=$(id -u ${user})
    sudo -u ${user} launchctl kickstart -k "gui/$USER_ID/local.darwin-startup" || sudo -u ${user} "${startupScript}/bin/darwin-startup"

    # Following line should allow us to avoid a logout/login cycle when changing settings
    sudo -u ${user} /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
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
      "com.apple.HIToolbox" = {
        AppleCurrentKeyboardLayoutInputSourceID = "com.apple.keylayout.US";
        AppleDictationAutoEnable = 1;
        AppleEnabledInputSources = [
          {
            InputSourceKind = "Keyboard Layout";
            "KeyboardLayout ID" = 0;
            "KeyboardLayout Name" = "U.S.";
          }
          {
            "Bundle ID" = "com.apple.CharacterPaletteIM";
            InputSourceKind = "Non Keyboard Input Method";
          }
          {
            InputSourceKind = "Keyboard Layout";
            "KeyboardLayout ID" = 19458;
            "KeyboardLayout Name" = "RussianWin";
          }
          {
            "Bundle ID" = "com.apple.inputmethod.ironwood";
            InputSourceKind = "Non Keyboard Input Method";
          }
        ];
        AppleFnUsageType = 1;
      };
      "NSGlobalDomain" = {
        AppleHighlightColor = "0.968627 0.831373 1.000000 Purple";
        AppleLanguages = [
          "en-US"
          "de-DE"
          "ru-DE"
        ];
        AppleLocale = "en_US@rg=dezzzz";
      };
      "com.apple.symbolichotkeys" = {
        AppleSymbolicHotKeys = {
          # Disable '^ + Space' for selecting the previous input source
          "60" = {
            enabled = true;
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
      "com.apple.dock" = {
        enterMissionControlByTopWindowDrag = true;
      };
      "com.apple.finder" = {
        FK_AppCentricShowSidebar = true;
      };
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
      "com.pilotmoon.scroll-reverser" = {
        ReverseMouse = false;
        ReverseTrackpad = true;
        InvertScrollingOn = true;
        ShowDiscreteScrollOptions = true;
      };
      "com.sbmpost.AutoRaise" = {
        autoFocusDelay = 55;
        autoRaiseDelay = 0;
        enableOnLaunch = true;
        ignoreSpaceChanged = false;
      };
      "com.raycast.macos" = {
        navigationCommandStyleIdentifierKey = "vim";
        "fileSearch_fileSearchScope" = "kMDQueryScopeHome";
      };
      "com.doomlaser.cursorcerer" = {
        "idleHide" = 5.0;
        "enabled" = true;
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
      mru-spaces = false;
      wvous-tl-corner = 1;
      wvous-br-corner = 1;
      persistent-apps = [ ];
      persistent-others = [ ];
    };

    spaces = {
      spans-displays = true;
    };

    # Finder settings
    finder = {
      AppleShowAllFiles = true;
      FXDefaultSearchScope = "SCcf"; # Search current folder
      ShowPathbar = true;
      ShowStatusBar = true;
      _FXShowPosixPathInTitle = true;
    };

    # Login window settings
    loginwindow = {
      GuestEnabled = false;
      SHOWFULLNAME = false;
    };

    # Menu bar settings
    menuExtraClock = {
      ShowAMPM = true;
      ShowDate = 0;
      ShowDayOfWeek = true;
    };

    # Screen Capture
    screencapture = {
      location = "~/Documents/Screenshots";
      type = "png";
      disable-shadow = true;
    };

    # NSGlobalDomain settings (system-wide preferences)
    NSGlobalDomain = {
      "com.apple.swipescrolldirection" = false; # true = natural scrolling
      "com.apple.trackpad.scaling" = 1.0;

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

      # Keyboard
      AppleKeyboardUIMode = 3;
      ApplePressAndHoldEnabled = false;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;

      # Spaces
      AppleSpacesSwitchOnActivate = true;
    };

    # Trackpad settings
    trackpad = {
      Clicking = true;
      Dragging = true;
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = false;
    };
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
