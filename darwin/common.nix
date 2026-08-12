{
  pkgs,
  lib,
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

    # 1. Karabiner VirtualHIDDevice Driver Setup
    # We only need the VirtualHIDDevice Daemon + dext for Kanata to emit keystrokes.
    # We intentionally NEVER open Karabiner-Elements.app because doing so launches
    # karabiner_grabber, which opens HID keyboards exclusively via the dext.
    #
    # If the grabber loses Input Monitoring TCC permission (OS update, JAMF/CrowdStrike
    # policy changes), it enters a deadlock: it holds exclusive device access but TCC
    # blocks it from reading events. This blocks ALL keyboard input system-wide,
    # including external keyboards. The grabber auto-respawns via internal XPC/launchd,
    # so pkill/bootout is insufficient — we must prevent it from ever executing.
    KARABINER_BIN="/Library/Application Support/org.pqrs/Karabiner-Elements/bin"
    if [ -x "$KARABINER_BIN/karabiner_grabber" ]; then
      echo "Ensuring Karabiner grabber and GUI processes cannot execute..."
      sudo chmod -x "$KARABINER_BIN/karabiner_grabber" 2>/dev/null || true
      sudo chmod -x "$KARABINER_BIN/karabiner_console_user_server" 2>/dev/null || true
      sudo chmod -x "$KARABINER_BIN/karabiner_session_monitor" 2>/dev/null || true
      sudo pkill -9 -f karabiner_grabber 2>/dev/null || true
    fi

    # VirtualHIDDevice-Daemon auto-starts via its own launchd plist at boot.
    # If it isn't running (e.g. after a fresh install), start it so Kanata has
    # the virtual keyboard device to emit through.
    if ! ioreg -rn "Karabiner VirtualHIDKeyboard" >/dev/null 2>&1; then
      echo "VirtualHIDKeyboard not found — ensuring daemon is started..."
      VIRTUALHID_DAEMON="/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
      if [ -x "$VIRTUALHID_DAEMON" ]; then
        sudo /bin/launchctl kickstart -k system/org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon 2>/dev/null || \
          "$VIRTUALHID_DAEMON" &
        sleep 2
      fi
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
      # "FineTune" - prevent audio source switching, disabled until fixed
    )

    for app in "''${ensure_apps[@]}"; do
      if ! pgrep -x "$app" >/dev/null; then
        if [ -d "/Applications/$app.app" ] || [ -d "/Applications/Nix Apps/$app.app" ] || [ -d "$USER_HOME/Applications/$app.app" ] || [ -d "$USER_HOME/Applications/Home Manager Apps/$app.app" ]; then
          echo "Starting $app (was not running)..."

          # If we are starting Hammerspoon, we need sketchybar running first.
          # HS's integrations.init() checks pgrep and only schedules updates if
          # sketchybar is alive. If HS launches sketchybar itself, the init
          # holds the AX lock and freezes HS's event loop.
          if [ "$app" == "Hammerspoon" ]; then
             pkill -x "sketchybar" 2>/dev/null || true
             sleep 0.5
             /bin/zsh -lc "sketchybar >/dev/null 2>&1 & disown" 2>/dev/null
             # Post-boot event-tap fix: HS's event tap (hotkeys) often fails
             # silently when the TCC/Accessibility service hasn't fully initialized
             # yet at login. Reload HS after a grace period — IPC reload if the
             # module loaded successfully, else kill+restart.
             (sleep 5; /opt/homebrew/bin/hs -c 'hs.reload()' 2>/dev/null || { pkill -x Hammerspoon; sleep 1; open -a Hammerspoon; }) &
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
    (import ../nixos/common/overlays.nix { inherit inputs; })
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
    %admin ALL=(ALL) NOPASSWD: SETENV: /bin/chmod
    %admin ALL=(ALL) NOPASSWD: /usr/bin/log
  '';

  launchd.agents.darwin-startup = {
    command = "/usr/local/bin/darwin-startup";
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
      # cleanup = "none";
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
      "ollama"
    ];

    taps = [
      "FelixKratz/formulae"
      "dimentium/autoraise"
      "k06a/tap"
    ];
  };

  system.activationScripts.homebrew.text = lib.mkBefore ''
    echo "Trusting third-party Homebrew taps..."
    sudo -u ${user} HOME=/Users/${user} /opt/homebrew/bin/brew trust dimentium/autoraise felixkratz/formulae k06a/tap || true
    sudo -u ${user} HOME=/Users/${user} /opt/homebrew/bin/brew trust --formula k06a/tap/macpow || true
  '';

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

    # Setup password-store symlink (pass expects ~/.password-store)
    echo "Setting up password-store symlink..."
    if [ ! -e "/Users/${user}/.password-store" ]; then
      ln -sf "/Users/${user}/configs/nixos-configs/secrets/passwords" "/Users/${user}/.password-store"
    fi

    # Configure gpg-agent to use pinentry-mac for GUI passphrase prompts
    echo "Configuring gpg-agent..."
    mkdir -p "/Users/${user}/.gnupg"
    chmod 700 "/Users/${user}/.gnupg"
    GPGAGENT_CONF="/Users/${user}/.gnupg/gpg-agent.conf"
    PINENTRY_PATH="/etc/profiles/per-user/${user}/bin/pinentry-mac"
    # Always keep pinentry-program up to date (strip stale line, append fresh)
    touch "$GPGAGENT_CONF"
    grep -v "pinentry-program" "$GPGAGENT_CONF" > "$GPGAGENT_CONF.tmp" 2>/dev/null || true
    echo "pinentry-program $PINENTRY_PATH" >> "$GPGAGENT_CONF.tmp"
    mv "$GPGAGENT_CONF.tmp" "$GPGAGENT_CONF"
    chown -R ${user} "/Users/${user}/.gnupg"

    # Setup firefoxpwa
    echo "Linking firefoxpwa native messaging host..."
    mkdir -p "/Library/Application Support/Mozilla/NativeMessagingHosts"
    ln -sf "/opt/homebrew/opt/firefoxpwa/share/firefoxpwa.json" "/Library/Application Support/Mozilla/NativeMessagingHosts/firefoxpwa.json"

    # Setup firenvim native messaging host
    echo "Setting up firenvim native messaging host..."
    if [ -d "/Applications/Firefox.app" ] || [ -d "/Users/${user}/Applications/Firefox.app" ] || [ -d "/Users/${user}/Applications/Home Manager Apps/Firefox.app" ]; then
      sudo -u ${user} /bin/zsh -lc "nvim --headless '+call firenvim#install(0)' +quit" 2>/dev/null || true
    fi

    # Safely set cursor settings via defaults write as the user
    echo "Setting cursor size, colors, and other universal access settings..."
    sudo -u ${user} /bin/bash -c '
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

    # Setup darwin-startup stable path to prevent Gatekeeper prompts.
    # The launchd plist at /Library/LaunchAgents/local.darwin-startup.plist is
    # regenerated on every rebuild with a Nix-store ProgramArguments hash. macOS
    # provenance tracking flags the changed executable, triggering a "security
    # permissions" dialog. Copying to a stable path decouples the plist contents
    # from Nix rebuilds.
    echo "Ensuring darwin-startup stable path..."
    DARWIN_STARTUP_DEST=/usr/local/bin/darwin-startup
    if ! cmp -s ${startupScript}/bin/darwin-startup "$DARWIN_STARTUP_DEST"; then
      cp -f ${startupScript}/bin/darwin-startup "$DARWIN_STARTUP_DEST"
      chmod 755 "$DARWIN_STARTUP_DEST"
    fi

    # Trigger user-level startup script now that the stable path exists.
    echo "Triggering user-level startup script via launchd..."
    USER_ID=$(id -u ${user})
    sudo -u ${user} launchctl kickstart -k "gui/$USER_ID/local.darwin-startup" || sudo -u ${user} /usr/local/bin/darwin-startup

    # Bootstrap a persistent local code-signing identity for kanata-nix so
    # Input Monitoring / Accessibility TCC grants survive future binary
    # updates. Ad-hoc signing ("codesign -s -") on a bare (non-bundled)
    # binary auto-generates a fresh identifier+CDHash on every signature, and
    # TCC pins its designated requirement to that CDHash - any rebuild that
    # changes the binary's content invalidates the existing grant. A
    # self-signed certificate anchors the designated requirement to
    # "identifier + certificate leaf" instead, which stays stable across
    # content changes. The key is generated locally, imported straight into
    # the System keychain, and never written to the repo or leaves this Mac -
    # each machine bootstraps (and trusts) its own local-only identity.
    KANATA_CODESIGN_IDENTITY="kanata-local-codesign"
    if ! security find-identity -v -p codesigning /Library/Keychains/System.keychain 2>/dev/null | grep -q "$KANATA_CODESIGN_IDENTITY"; then
      echo "Bootstrapping persistent local code-signing identity ($KANATA_CODESIGN_IDENTITY)..."
      CERT_DIR=$(mktemp -d)
      ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:2048 \
        -keyout "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem" -days 3650 -nodes \
        -subj "/CN=$KANATA_CODESIGN_IDENTITY" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1
      P12_PASS=$(${pkgs.openssl}/bin/openssl rand -base64 24)
      ${pkgs.openssl}/bin/openssl pkcs12 -export -legacy \
        -out "$CERT_DIR/cert.p12" -inkey "$CERT_DIR/key.pem" -in "$CERT_DIR/cert.pem" \
        -passout "pass:$P12_PASS" >/dev/null 2>&1
      security import "$CERT_DIR/cert.p12" -k /Library/Keychains/System.keychain -P "$P12_PASS" -T /usr/bin/codesign -A
      security add-trusted-cert -d -r trustRoot -p codeSign "$CERT_DIR/cert.pem"
      rm -rf "$CERT_DIR"
      echo "> Created and trusted $KANATA_CODESIGN_IDENTITY for local code signing."
    fi

    pkill -x warpd || true
    pkill -9 kanata || true
    # Setup kanata stable path for Input Monitoring permissions
    # Binary update is opt-in to avoid unnecessary rebuild churn.
    # Signed with the persistent "kanata-local-codesign" identity (System keychain) so the
    # designated requirement is "identifier + certificate leaf", not a raw content hash -
    # Input Monitoring permission survives binary updates instead of needing to be re-granted.
    # To update kanata: touch ~/.config/kanata/update-kanata && darwin-rebuild switch
    echo "Ensuring kanata stable binary path for Input Monitoring permissions..."
    mkdir -p /usr/local/bin
    KANATA_UPDATE_FLAG="/Users/${user}/.config/kanata/update-kanata"
    if [ -f "$KANATA_UPDATE_FLAG" ]; then
      echo "User requested kanata update. Copying binary..."
      cp -f ${unstable.kanata}/bin/kanata /usr/local/bin/kanata-nix
      chmod 755 /usr/local/bin/kanata-nix
      codesign --force -s "kanata-local-codesign" -i "local.kanata.kanata-nix" /usr/local/bin/kanata-nix 2>/dev/null || true
      rm -f "$KANATA_UPDATE_FLAG"
    elif [ ! -f /usr/local/bin/kanata-nix ]; then
      echo "First install: copying kanata-nix binary..."
      cp -f ${unstable.kanata}/bin/kanata /usr/local/bin/kanata-nix
      chmod 755 /usr/local/bin/kanata-nix
      codesign --force -s "kanata-local-codesign" -i "local.kanata.kanata-nix" /usr/local/bin/kanata-nix 2>/dev/null || true
      echo "> Grant Input Monitoring permission to /usr/local/bin/kanata-nix in System Settings"
    else
      # Compare --version output rather than raw bytes: codesign embeds a
      # signature into the local copy after it's copied, so its bytes never
      # match the pristine (unsigned) store binary even when the version is
      # identical - a raw `cmp` here always false-positives on "update available".
      STORE_KANATA_VERSION=$(${unstable.kanata}/bin/kanata --version 2>/dev/null || echo "unknown")
      LOCAL_KANATA_VERSION=$(/usr/local/bin/kanata-nix --version 2>/dev/null || echo "unknown")
      if [ "$STORE_KANATA_VERSION" != "$LOCAL_KANATA_VERSION" ]; then
        echo "> Kanata update available ($LOCAL_KANATA_VERSION -> $STORE_KANATA_VERSION) but NOT applied."
        echo "> To update: touch ~/.config/kanata/update-kanata && darwin-rebuild switch"
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

  # Enable Remote Login (SSH)
  services.openssh.enable = true;

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
