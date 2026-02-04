{ pkgs, lib, unstable, ... }:

let
  spoon =
    name: sha256:
    pkgs.fetchzip {
      url = "https://github.com/Hammerspoon/Spoons/raw/master/Spoons/${name}.spoon.zip";
      inherit sha256;
    };
in
{

  home.username = "andreishumailov";
  home.homeDirectory = lib.mkForce "/Users/andreishumailov";

  imports = [
    # Import common configurations with macOS guards
    ../home-manager/common/default.nix
    ./git.nix
  ];

  # macOS-specific packages
  home.packages =
    with pkgs;
    [
      # macOS-specific utilities
      mas # Mac App Store CLI
      m-cli # Swiss Army Knife for macOS

      # Development tools that work well on macOS
      colima # Container runtime for macOS
      lazydocker # Terminal UI for docker

      # Additional macOS tools
      duti # Default application handler

      # Window management
      sketchybar # Status bar
      nowplaying-cli # Media info for sketchybar

      shortcat
      macmon

      jankyborders
      unstable.claude-code
      unstable.gemini-cli

      (writeShellScriptBin "pip-pop" (lib.readFile ./scripts/pip-pop))
      (writeShellScriptBin "fullscreen-raise" (lib.readFile ./scripts/fullscreen-raise))
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [
      # Darwin-specific packages
    ];

  # macOS-specific shell aliases
  programs.zsh.shellAliases = pkgs.lib.mkMerge [
    {
      # macOS-specific aliases
      sup = "sudo darwin-rebuild switch --flake $HOME/configs/nixos-configs/#mac-work --impure";

      # macOS system management
      flush-dns = "sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder";
      show-hidden = "defaults write com.apple.finder AppleShowAllFiles -bool true && killall Finder";
      hide-hidden = "defaults write com.apple.finder AppleShowAllFiles -bool false && killall Finder";

      # Docker/Colima shortcuts - optimized for testcontainers
      docker-start = "colima start --cpu 4 --memory 8 --disk 60 --network-address";
      docker-stop = "colima stop";
      docker-status = "colima status";
      docker-env = "colima-testcontainers-env";
      lzd = "lazydocker";

      # AeroSpace shortcuts
      aerospace-reload = "aerospace reload-config";
      aerospace-list = "aerospace list-windows --all";
      aerospace-debug = "aerospace debug-windows";

      # Clipboard shortcuts
      clipboard-history = "open -a Maccy";
      clipboard-clear = "defaults delete org.p0deje.Maccy";

      # Kanata configuration management
      reload-kanata = "~/.config/kanata/reload-kanata.sh";
      reload-kanata-logs = "~/.config/kanata/reload-kanata.sh --show-logs";
    }
  ];

  # macOS-specific programs configuration
  programs.git = {
    settings = {
      # macOS-specific git settings
      credential.helper = "osxkeychain";
    };
  };

  # macOS-specific home files
  home.file = {
    # macOS-specific dotfiles can go here
    ".hushlogin".text = ""; # Suppress login message

    ".config/aerospace/aerospace.toml".source = ../../dotfiles/aerospace/aerospace.toml;

    # Maccy configuration
    ".config/maccy/maccy-config.sh".source = ../../dotfiles/maccy/maccy-config.sh;

    # Karabiner-Elements configuration
    ".config/karabiner/karabiner.json".source = ../../dotfiles/karabiner/karabiner.json;

    # Kanata configuration (home row mods only)
    ".config/kanata/kanata.kbd".source = ../../dotfiles/kanata/kanata.kbd;
    ".config/kanata/reload-kanata.sh".source = ../../dotfiles/kanata/reload-kanata.sh;

    # Colima/Testcontainers helper script
    ".local/bin/colima-testcontainers-env" = {
      executable = true;
      text = ''
        #!/bin/bash
        # Helper script to set up environment for testcontainers with colima
        # Run this script with: eval "$(colima-testcontainers-env)"
        # Or source it: source <(colima-testcontainers-env)

        # Check if colima is running
        if ! colima status &>/dev/null; then
          echo "# Colima is not running. Start it with: docker-start" >&2
          echo "# Then run: eval \"\$(colima-testcontainers-env)\"" >&2
          exit 1
        fi

        # Get colima VM IP address
        COLIMA_IP=$(colima ls -j 2>/dev/null | jq -r '.address // empty')

        if [ -z "$COLIMA_IP" ]; then
          # Fallback: try to get IP from colima ssh
          COLIMA_IP=$(colima ssh -- hostname -I 2>/dev/null | awk '{print $1}')
        fi

        echo "export DOCKER_HOST=\"unix://\$HOME/.colima/default/docker.sock\""
        echo "export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=\"/var/run/docker.sock\""
        echo "export TESTCONTAINERS_RYUK_DISABLED=\"false\""

        if [ -n "$COLIMA_IP" ]; then
          echo "export TESTCONTAINERS_HOST_OVERRIDE=\"$COLIMA_IP\""
          echo "# Colima IP: $COLIMA_IP" >&2
        else
          echo "# Warning: Could not determine colima IP address" >&2
          echo "# Some testcontainers features may not work correctly" >&2
        fi

        echo "# Testcontainers environment configured for colima" >&2
      '';
    };

    # JankyBorders configuration
    ".config/borders/bordersrc" = {
      executable = true;
      text = ''
        #!/bin/bash
        # JankyBorders configuration - Tokyo Night theme
        # Toggle with Ctrl+Alt+B in Hammerspoon (smart mode: auto-hides with 1 window or monocle)

        borders \
          style=round \
          width=4.0 \
          hidpi=on \
          active_color=0xff7b5cff \
          inactive_color=0xff3b4261 \
          blacklist="Raycast,System Settings,Finder,Archive Utility,App Store,Hammerspoon,Disk Utility,Calculator"
      '';
    };

    # Hammerspoon
    ".hammerspoon/init.lua".source = ../../dotfiles/hammerspoon/init.lua;
    ".hammerspoon/macos-vim-navigation/init.lua".source =
      ../../dotfiles/hammerspoon/macos-vim-navigation/init.lua;

    # NanoWM modular window manager
    ".hammerspoon/nanowm/init.lua".source = ../../dotfiles/hammerspoon/nanowm/init.lua;
    ".hammerspoon/nanowm/config.lua".source = ../../dotfiles/hammerspoon/nanowm/config.lua;
    ".hammerspoon/nanowm/state.lua".source = ../../dotfiles/hammerspoon/nanowm/state.lua;
    ".hammerspoon/nanowm/core.lua".source = ../../dotfiles/hammerspoon/nanowm/core.lua;
    ".hammerspoon/nanowm/layout.lua".source = ../../dotfiles/hammerspoon/nanowm/layout.lua;
    ".hammerspoon/nanowm/actions.lua".source = ../../dotfiles/hammerspoon/nanowm/actions.lua;
    ".hammerspoon/nanowm/tags.lua".source = ../../dotfiles/hammerspoon/nanowm/tags.lua;
    ".hammerspoon/nanowm/menus.lua".source = ../../dotfiles/hammerspoon/nanowm/menus.lua;
    ".hammerspoon/nanowm/integrations.lua".source = ../../dotfiles/hammerspoon/nanowm/integrations.lua;
    ".hammerspoon/nanowm/keybinds.lua".source = ../../dotfiles/hammerspoon/nanowm/keybinds.lua;
    ".hammerspoon/nanowm/watchers.lua".source = ../../dotfiles/hammerspoon/nanowm/watchers.lua;

    # Hammerspoon Spoons
    ".hammerspoon/Spoons/AClock.spoon".source =
      spoon "AClock" "0swzy9wvgjc93l0qc89m0zk9j0xk14w71v38vqfy2b96f4qd59p4";
    ".hammerspoon/Spoons/PaperWM.spoon".source = pkgs.fetchzip {
      url = "https://github.com/mogenson/PaperWM.spoon/archive/main.zip";
      sha256 = "0swzy9wvgjc93l0qc89m0zk9j0xk14w71v38vqfy2b96f4qd59p4";
    };
    ".hammerspoon/Spoons/VimMode.spoon".source = pkgs.fetchzip {
      url = "https://github.com/dbalatero/VimMode.spoon/archive/master.zip";
      sha256 = "0ihpg5ipl60gkvwcmlcvjca2b6y0v3lv50dhyz7nicnh3yb7d76f";
    };

    # --- SketchyBar Config ---
    ".config/sketchybar/sketchybarrc" = {
      executable = true;
      source = ../../dotfiles/sketchybar/sketchybarrc;
    };

    # --- SketchyBar Plugins ---
    ".config/sketchybar/plugins/space.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/space.sh;
    };
    ".config/sketchybar/plugins/space_click.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/space_click.sh;
    };
    ".config/sketchybar/plugins/front_app.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/front_app.sh;
    };
    ".config/sketchybar/plugins/nanowm_timer.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/nanowm_timer.sh;
    };
    ".config/sketchybar/plugins/nanowm_layout.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/nanowm_layout.sh;
    };
    ".config/sketchybar/plugins/sep_timer.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/sep_timer.sh;
    };
    ".config/sketchybar/plugins/caffeinate.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/caffeinate.sh;
    };
    ".config/sketchybar/plugins/datetime.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/datetime.sh;
    };
    ".config/sketchybar/plugins/volume.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/volume.sh;
    };
    ".config/sketchybar/plugins/cpu_graph.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/cpu_graph.sh;
    };
    ".config/sketchybar/plugins/memory.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/memory.sh;
    };
    ".config/sketchybar/plugins/battery.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/battery.sh;
    };
    ".config/sketchybar/plugins/battery_click.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/battery_click.sh;
    };
    ".config/sketchybar/plugins/power.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/power.sh;
    };
    ".config/sketchybar/plugins/power_click.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/power_click.sh;
    };
    ".config/sketchybar/plugins/network.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/network.sh;
    };
  };

  # macOS-specific environment variables
  home.sessionVariables = {
    # macOS-specific environment
    BROWSER = "open";

    # Docker/Colima configuration for testcontainers compatibility
    # Point to colima's docker socket
    DOCKER_HOST = "unix://\${HOME}/.colima/default/docker.sock";

    # Testcontainers configuration for colima
    # This tells testcontainers where the docker socket is inside the VM
    TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE = "/var/run/docker.sock";

    # Ryuk is the container that cleans up after tests - needs to be enabled
    TESTCONTAINERS_RYUK_DISABLED = "false";
  };

  home.stateVersion = "25.11";
}
