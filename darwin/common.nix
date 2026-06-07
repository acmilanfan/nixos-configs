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
    # We only open it if drivers aren't loaded, then clean up GUI components
    if [ -d "/Applications/Karabiner-Elements.app" ]; then
      # Check if virtual device is already present
      if ! ioreg -rn "Karabiner VirtualHIDDevice" >/dev/null 2>&1; then
        echo "Initializing Karabiner-Elements drivers..."
        open -a "Karabiner-Elements"
        sleep 2
      fi

      echo "Cleaning up Karabiner GUI components and grabber..."
      # Run cleanup in background where possible
      (
        osascript -e 'quit app "Karabiner-Elements"' 2>/dev/null || true
        sudo launchctl disable system/org.pqrs.service.daemon.Karabiner-Core-Service 2>/dev/null || true
        sudo launchctl bootout system/org.pqrs.service.daemon.Karabiner-Core-Service 2>/dev/null || true
        sudo launchctl disable system/org.pqrs.service.daemon.karabiner_grabber 2>/dev/null || true
        sudo launchctl bootout system/org.pqrs.service.daemon.karabiner_grabber 2>/dev/null || true
      ) &

      # Kill all Karabiner related processes immediately
      pkill -x "Karabiner-Menu" 2>/dev/null || true
      pkill -x "Karabiner-NotificationWindow" 2>/dev/null || true
      pkill -x "karabiner_console_user_server" 2>/dev/null || true
      pkill -x "karabiner_grabber" 2>/dev/null || true
      sudo killall Karabiner-Core-Service 2>/dev/null || true
      sudo killall karabiner_grabber 2>/dev/null || true
      sudo pkill -9 kanata 2>/dev/null || true

      # NOTE: We do NOT stop Karabiner-VirtualHIDDevice-Daemon because Kanata
      # depends on it to emit keystrokes. Stopping it causes a total keyboard blackout.
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
      "Syncthing"
      "Warpd"
      "FineTune"
    )

    for app in "''${ensure_apps[@]}"; do
      if ! pgrep -x "$app" >/dev/null; then
        if [ -d "/Applications/$app.app" ] || [ -d "/Applications/Nix Apps/$app.app" ] || [ -d "$USER_HOME/Applications/$app.app" ] || [ -d "$USER_HOME/Applications/Home Manager Apps/$app.app" ]; then
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

    # 5. File Associations
    echo "Updating file associations with duti..."
    APP_BUNDLE_ID="com.gentooway.nvim-opener"
    # Register the application
    for app_path in "/Applications/Nix Apps/NvimOpener.app" "/Applications/NvimOpener.app" "$USER_HOME/Applications/Home Manager Apps/NvimOpener.app"; do
      if [ -d "$app_path" ]; then
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_path"
      fi
    done

    # Set associations
    if command -v duti >/dev/null; then
      duti -s $APP_BUNDLE_ID .org all
      duti -s $APP_BUNDLE_ID .txt all
      duti -s $APP_BUNDLE_ID .md all
      duti -s $APP_BUNDLE_ID .nix all
    fi

    echo "Startup script completed."
  '';
in
{
  ## TODO things to fix
  # - firenvim does not work
  # - keyboard BT control

  environment.systemPackages = with pkgs; [
    vim
    curl
    wget
    tree
    zsh
    unstable.aerospace
    startupScript
    pkgs.warpd
    unstable.kanata
    pkgs.blueutil-tui
    pkgs.nvim-opener
  ];

  nixpkgs.overlays = [
    (import ../nixos/common/overlays.nix)
  ];

  launchd.daemons.kanata = {
    command = "/bin/bash -c 'exec /usr/local/bin/kanata-nix -n --cfg /Users/${user}/.config/kanata/active_config.kbd --port 5829'";

    serviceConfig = {
      Label = "local.kanata";
      KeepAlive = true;
      RunAtLoad = true;
      ProcessType = "Interactive";
      StandardOutPath = "/tmp/kanata.log";
      StandardErrorPath = "/tmp/kanata.error.log";
    };
  };

  security.sudo.extraConfig = ''
    %admin ALL=(ALL) NOPASSWD: /usr/local/bin/kanata-nix
    %admin ALL=(ALL) NOPASSWD: /opt/homebrew/bin/kanata
    %admin ALL=(ALL) NOPASSWD: /usr/bin/killall
    %admin ALL=(ALL) NOPASSWD: /bin/launchctl
    %admin ALL=(ALL) NOPASSWD: /usr/bin/pkill
    %admin ALL=(ALL) NOPASSWD: /usr/bin/pmset
  '';

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
      autoUpdate = false;
      # autoUpdate = true;
      upgrade = false;
      # upgrade = true;
    };

    casks = [
      "google-chrome"
      "firefox"
      "slack"
      "raycast"
      "karabiner-elements"
      "cleanupbuddy"
      "nextcloud"
      "kitty"
      "dimentium/autoraise/autoraiseapp"
      "scroll-reverser"
      "hammerspoon"
      "balenaetcher"
      "middleclick"
      "cursorcerer"
      "finetune"
    ];

    brews = [
      "mas"
      "scrcpy"
      "kanata"
      "firefoxpwa"
      "docker"
      "wifitui"
      "k06a/tap/macpow"
    ];

    taps = [
      "FelixKratz/formulae"
      "dimentium/autoraise"
      "k06a/tap"
    ];
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
    optimise = {
      automatic = true;
      interval = {
        Weekday = 0;
        Hour = 4;
        Minute = 0;
      };
    };
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
    if [ -d "/Applications/Firefox.app" ] || [ -d "/Users/${user}/Applications/Firefox.app" ] || [ -d "/Users/${user}/Applications/Home Manager Apps/Firefox.app" ]; then
      sudo -u ${user} /bin/zsh -lc "nvim --headless '+call firenvim#install(0)' +quit" 2>/dev/null || true
    fi

    # Run user-level startup tasks (apps, drivers)
    # We use kickstart to run the agent in the proper GUI session context
    echo "Triggering user-level startup script via launchd..."
    USER_ID=$(id -u ${user})
    sudo -u ${user} launchctl kickstart -k "gui/$USER_ID/local.darwin-startup" || sudo -u ${user} "${startupScript}/bin/darwin-startup"

    # Safely set cursor settings via defaults write as the user
    echo "Setting cursor size, colors, and other universal access settings..."
    sudo -u ${user} bash -c '
      export PATH=$PATH:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin
      defaults write com.apple.universalaccess cursorIsCustomized -bool true

      # Fix for macOS Tahoe/Sequoia menu bar and glass style
      defaults write -g NSGlassDiffusionSetting -bool true
      defaults write -g SLSMenuBarUseBlurredAppearance -bool true

      # Battery charge threshold (macOS 26.4+)
      defaults write com.apple.batteryui.charging.mac com.apple.batteryui.charging.mac.prior.limit -float 80.0

      # Set cursor fill (Black)
      defaults write com.apple.universalaccess cursorFill -dict \
        red -float 0 \
        green -float 0 \
        blue -float 0 \
        alpha -float 1

      # Set cursor outline (Purple)
      defaults write com.apple.universalaccess cursorOutline -dict \
        red -float 1 \
        green -float 0.7983930706977844 \
        blue -float 0.9761069416999817 \
        alpha -float 1
    '

    # Following line should allow us to avoid a logout/login cycle when changing settings
    sudo -u ${user} /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
    sudo -u ${user} killall universalaccessd SystemUIServer Dock WindowManager batteryui 2>/dev/null || true

    # Clear quarantine attribute for Hammerspoon to prevent IPC hook prompts
    echo "Clearing quarantine attributes for Hammerspoon..."
    xattr -r -d com.apple.quarantine /Applications/Hammerspoon.app 2>/dev/null || true

    # Setup warpd stable path for permissions
    echo "Ensuring warpd stable binary path for permissions..."
    mkdir -p /usr/local/bin

    # Only copy if binary is different to avoid invalidating TCC permissions
    if ! cmp -s ${pkgs.warpd}/bin/warpd /usr/local/bin/warpd-nix; then
      echo "Updating warpd-nix binary..."
      cp -f ${pkgs.warpd}/bin/warpd /usr/local/bin/warpd-nix
      chmod 755 /usr/local/bin/warpd-nix
      codesign --force -s - /usr/local/bin/warpd-nix 2>/dev/null || true
    fi

    pkill -x warpd || true
    pkill -9 kanata || true
    # Setup kanata stable path for Input Monitoring permissions
    # Binary update is opt-in to preserve TCC Input Monitoring permission across nix updates.
    # macOS ties the permission to the binary's code signature hash, which changes on every update.
    # To update kanata: touch ~/.config/kanata/update-kanata && darwin-rebuild switch
    echo "Ensuring kanata stable binary path for Input Monitoring permissions..."
    mkdir -p /usr/local/bin
    KANATA_UPDATE_FLAG="/Users/${user}/.config/kanata/update-kanata"
    if [ -f "$KANATA_UPDATE_FLAG" ]; then
      echo "User requested kanata update. Copying binary..."
      cp -f ${unstable.kanata}/bin/kanata /usr/local/bin/kanata-nix
      chmod 755 /usr/local/bin/kanata-nix
      codesign --force -s - /usr/local/bin/kanata-nix 2>/dev/null || true
      rm -f "$KANATA_UPDATE_FLAG"
      echo "> IMPORTANT: You MUST re-grant Input Monitoring permission to /usr/local/bin/kanata-nix"
      echo "> Open: System Settings > Privacy & Security > Input Monitoring"
      echo "> Toggle OFF then ON for /usr/local/bin/kanata-nix (or re-add it)"
    elif [ ! -f /usr/local/bin/kanata-nix ]; then
      echo "First install: copying kanata-nix binary..."
      cp -f ${unstable.kanata}/bin/kanata /usr/local/bin/kanata-nix
      chmod 755 /usr/local/bin/kanata-nix
      codesign --force -s - /usr/local/bin/kanata-nix 2>/dev/null || true
      echo "> Grant Input Monitoring permission to /usr/local/bin/kanata-nix in System Settings"
    else
      if ! cmp -s ${unstable.kanata}/bin/kanata /usr/local/bin/kanata-nix; then
        echo "> Kanata update available but NOT applied (to preserve Input Monitoring permission)."
        echo "> To update: touch ~/.config/kanata/update-kanata && darwin-rebuild switch"
        echo "> After updating, re-grant Input Monitoring permission to /usr/local/bin/kanata-nix"
      fi
    fi

    # Power management (balanced: powernap off, wake-on-LAN off, TCPKeepAlive off)
    echo "Applying power management settings..."
    sudo pmset -b displaysleep 3 disksleep 10 sleep 10 powernap 0 womp 0 || true
    sudo pmset -c displaysleep 10 disksleep 30 sleep 30 powernap 0 womp 0 || true
    sudo pmset -a hibernatemode 3 standby 1 standbydelaylow 600 standbydelayhigh 3600 || true

    # Spotlight: exclude subdirectories by planting a .metadata_never_index marker.
    # mdutil -i off only works on volumes; for subdirs mds respects this file.
    echo "Excluding paths from Spotlight indexing..."
    for p in \
      "/Users/${user}/.cache" \
      "/Users/${user}/.colima" \
      "/Users/${user}/Library/Containers" \
      "/Users/${user}/Library/Caches" \
      "/Users/${user}/.m2" \
      "/Users/${user}/.gradle" \
      "/Users/${user}/.cargo" \
      "/Users/${user}/.rustup" \
      "/Users/${user}/.npm" \
      "/Users/${user}/.nix-profile" \
      "/opt/homebrew" \
      "/nix"; do
      [ -d "$p" ] && touch "$p/.metadata_never_index" 2>/dev/null || true
    done
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
    universalaccess = {
      # reduceTransparency = true;
      reduceMotion = true;
      mouseDriverCursorSize = 1.5;
    };
    CustomUserPreferences = {
      "NSGlobalDomain" = {
        NSGlassDiffusionSetting = true;
        SLSMenuBarUseBlurredAppearance = true;
        AppleHighlightColor = "0.968627 0.831373 1.000000 Purple";
        AppleLanguages = [
          "en-US"
          "de-DE"
          "ru-DE"
        ];
        AppleLocale = "en_US@rg=dezzzz";
      };
      "com.apple.batteryui.charging.mac" = {
        "com.apple.batteryui.charging.mac.prior.limit" = 80.0;
      };
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
      "com.apple.dock" = {
        enterMissionControlByTopWindowDrag = true;
        launchanim = false;
        "expose-animation-duration" = 0.1;
        "springboard-show-duration" = 0;
        "springboard-hide-duration" = 0;
        "springboard-page-duration" = 0;
      };
      "com.apple.finder" = {
        FK_AppCentricShowSidebar = true;
        AnimateWindowZoom = false;
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
      mineffect = "scale";
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
      NSScrollAnimationEnabled = false;
      NSDocumentSaveNewDocumentsToCloud = false;

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

  # Keyboard settings (remapping handled by Kanata)
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToEscape = false;
  };

  # Security settings
  security.pam.services.sudo_local.touchIdAuth = true;
  security.pam.services.sudo_local.reattach = true;
}
