{ pkgs, lib, unstable, secrets, ... }:

let
  spoon =
    name: sha256:
    pkgs.fetchzip {
      url = "https://github.com/Hammerspoon/Spoons/raw/master/Spoons/${name}.spoon.zip";
      inherit sha256;
    };
in
{
  imports = [
    # Import common configurations with macOS guards
    ../home-manager/common/default.nix
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

      # Not preinstalled on macOS (only ships as part of NixOS itself); needed
      # here purely to drive remote deploys to vm-hyprland (sup-vm-hyprland).
      nixos-rebuild

      # Additional macOS tools
      duti # Default application handler

      gh

      # Window management
      sketchybar # Status bar
      nowplaying-cli # Media info for sketchybar

      shortcat
      macmon
      blueutil
      switchaudio-osx

      jankyborders
      syncthing-macos
      syncmon
      tg2kobo
      yazi

      (pass.withExtensions (exts: [ exts.pass-otp ]))
      gnupg
      pinentry_mac
      # Scripts need to be handled. They were in ./scripts/ relative to mac-work/home.nix.
      # We need to make sure they are accessible.
      # (writeShellScriptBin "pip-pop" (lib.readFile ./scripts/pip-pop))
      # (writeShellScriptBin "fullscreen-raise" (lib.readFile ./scripts/fullscreen-raise))

      # Nvim scratchpad: bare `nvim` (not a store path) so the configured
      # programs.neovim wrapper + orgmode is used. Copies to clipboard on
      # :wq; :cq exits non-zero so pbcopy is skipped and clipboard is untouched.
      # Runs from a dedicated empty dir: orgmode's org_agenda_files globs
      # "$cwd/**/*.org" recursively, and GUI-launched (via `open`) processes
      # start with cwd "/" -- without this cd it walks the whole filesystem.
      (pkgs.writeShellScriptBin "nvim-scratchpad" ''
        SCRATCH_DIR="/tmp/nvim-scratchpad"
        SCRATCH_FILE="$SCRATCH_DIR/nvim_scratch.org"
        mkdir -p "$SCRATCH_DIR"
        : > "$SCRATCH_FILE"
        cd "$SCRATCH_DIR"
        nvim -c 'startinsert' "$SCRATCH_FILE" && /usr/bin/pbcopy < "$SCRATCH_FILE"
      '')

      (pkgs.writeShellScriptBin "create-utm-vm-hyprland"
        (lib.readFile ../vm-hyprland/scripts/create-utm-vm.sh))
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [
      # Darwin-specific packages
    ];

  # macOS-specific shell aliases
  programs.zsh.shellAliases = pkgs.lib.mkMerge [
    {
      # macOS-specific aliases
      sup = "sudo darwin-rebuild switch --flake $HOME/configs/nixos-configs --impure";

      # Remote-deploy config changes to the vm-hyprland UTM VM: build here
      # (via nix.linux-builder, since this Mac can't build aarch64-linux
      # natively) and push+activate over SSH, without touching the VM's own
      # clone. Target user must be gentooway (the only user vm-hyprland's
      # own config defines) - without it ssh silently falls back to the
      # local macOS username, which doesn't exist on the VM and can never
      # authenticate. Override the host with VM_HYPRLAND_HOST=<ip>
      # sup-vm-hyprland if "vm-hyprland" isn't resolvable (no mDNS/SSH
      # config alias set up).
      sup-vm-hyprland = "nixos-rebuild switch --flake $HOME/configs/nixos-configs#vm-hyprland --target-host \"gentooway@\${VM_HYPRLAND_HOST:-vm-hyprland}\" --build-host localhost --sudo --ask-sudo-password --impure";

      # macOS system management
      flush-dns = "sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder";
      show-hidden = "defaults write com.apple.finder AppleShowAllFiles -bool true && killall Finder";
      hide-hidden = "defaults write com.apple.finder AppleShowAllFiles -bool false && killall Finder";

      # Docker/Colima shortcuts - optimized for testcontainers
      docker-start = "colima start --cpu 4 --memory 8 --disk 60 --network-address";
      colima-light = "colima start --cpu 2 --memory 4 --disk 30 --network-address";
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
      switch-kanata = "~/.config/kanata/switch-kanata.sh";
      reload-kanata-logs = "~/.config/kanata/reload-kanata.sh --show-logs";

      # Sync Dashboard
      syncmon = "alacritty --title 'SyncMon Dashboard' -e syncmon";    }
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

    # Paths need adjustment to point to dotfiles relative to this new location
    # nixos/common/home-darwin.nix -> ../../dotfiles is correct if nixos/common is at same level as nixos/mac-work
    # dotfiles is in root/dotfiles.
    # root/nixos/common/home-darwin.nix
    # root/dotfiles
    # so ../../dotfiles is correct.

    ".config/aerospace/aerospace.toml".source = ../../dotfiles/aerospace/aerospace.toml;

    # Karabiner-Elements configuration
    ".config/karabiner/karabiner.json" = {
      source = ../../dotfiles/karabiner/karabiner.json;
      force = true;
    };

    # Kanata configuration
    ".config/kanata/kanata-homerow.kbd".source = ../../dotfiles/kanata/kanata.kbd;
    ".config/kanata/kanata-default.kbd".source = ../../dotfiles/kanata/kanata-default.kbd;
    ".config/kanata/kanata-split.kbd".source = ../../dotfiles/kanata/kanata-split.kbd;
    ".config/kanata/kanata-angle.kbd".source = ../../dotfiles/kanata/kanata-angle.kbd;
    ".config/kanata/kanata-disabled.kbd".source = ../../dotfiles/kanata/kanata-disabled.kbd;
    ".config/kanata/kanata-training.kbd".source = ../../dotfiles/kanata/kanata-training.kbd;
    # ".config/kanata/active_config.kbd".source = ../../dotfiles/kanata/kanata-default.kbd;
    ".config/kanata/reload-kanata.sh" = {
      source = ../../dotfiles/kanata/reload-kanata.sh;
      executable = true;
    };
    ".config/kanata/switch-kanata.sh" = {
      source = ../../dotfiles/kanata/switch-kanata.sh;
      executable = true;
    };

    # Hammerspoon configuration
    ".hammerspoon/sweep-remapper.lua".source = ../../dotfiles/hammerspoon/sweep-remapper.lua;

    # Warpd configuration
    ".config/warpd/config".source = ../../dotfiles/warpd/config;

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
          echo "# Then run: eval \"$(colima-testcontainers-env)\"" >&2
          exit 1
        fi

        # We use 127.0.0.1 because Colima automatically forwards ports from the VM to localhost.
        # Direct VM IP access (e.g. 192.168.64.x) often fails with "no route to host" on macOS.
        COLIMA_IP="127.0.0.1"

        echo "export DOCKER_HOST=\"unix://$HOME/.colima/default/docker.sock\""
        echo "export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=\"/var/run/docker.sock\""
        echo "export TESTCONTAINERS_RYUK_DISABLED=\"false\""

        if [ -n "$COLIMA_IP" ]; then
          echo "export TESTCONTAINERS_HOST_OVERRIDE=\"$COLIMA_IP\""
          echo "# Testcontainers host: $COLIMA_IP" >&2
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
          blacklist="Raycast,Vicinae,System Settings,Finder,Archive Utility,App Store,Hammerspoon,Disk Utility,Calculator"
      '';
    };

    # SyncMon configuration
    ".syncmon.yaml" = {
      text = ''
        syncthing:
          url: "http://127.0.0.1:8384"
          apikey: "${secrets.syncthing_api_key}"
        paths:
          org: "~/org"
          configs: "~/configs/nixos-configs"
          nextcloud: "~/Nextcloud"
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
    ".hammerspoon/nanowm/overview.lua".source = ../../dotfiles/hammerspoon/nanowm/overview.lua;
    ".hammerspoon/nanowm/integrations.lua".source = ../../dotfiles/hammerspoon/nanowm/integrations.lua;
    ".hammerspoon/nanowm/keybinds.lua".source = ../../dotfiles/hammerspoon/nanowm/keybinds.lua;
    ".hammerspoon/nanowm/watchers.lua".source = ../../dotfiles/hammerspoon/nanowm/watchers.lua;
    ".hammerspoon/nanowm/agents.lua".source = ../../dotfiles/hammerspoon/nanowm/agents.lua;
    ".hammerspoon/nanowm/profiler.lua".source = ../../dotfiles/hammerspoon/nanowm/profiler.lua;
    ".hammerspoon/nanowm/pass.lua".source = ../../dotfiles/hammerspoon/nanowm/pass.lua;
    ".hammerspoon/nanowm/spec.lua".source = ../../dotfiles/hammerspoon/nanowm/spec.lua;

    # Rofi-like menus
    # ".hammerspoon/rofi-menus/init.lua".source = ../../dotfiles/hammerspoon/rofi-menus/init.lua;
    # ".hammerspoon/rofi-menus/services-scan.sh".source =
    #   ../../dotfiles/hammerspoon/rofi-menus/services-scan.sh;

    # Hammerspoon Spoons
    ".hammerspoon/Spoons/AClock.spoon".source =
      spoon "AClock" "sha256-3/Kxl0oVg4VneSZAp6l8PaP/9XZAuvinOcwfvfdLDqI=";
    #".hammerspoon/Spoons/PaperWM.spoon".source = pkgs.fetchzip {
    #  url = "https://github.com/mogenson/PaperWM.spoon/archive/main.zip";
    #  sha256 = "0swzy9wvgjc93l0qc89m0zk9j0xk14w71v38vqfy2b96f4qd59p4";
    #};
    ".hammerspoon/Spoons/VimMode.spoon".source = pkgs.runCommand "VimMode.spoon" {} ''
      cp -r ${pkgs.fetchzip {
        url = "https://github.com/dbalatero/VimMode.spoon/archive/master.zip";
        sha256 = "C4WDpMVDF0zuDV4rZYx05gwn8YZf3tOGegBj8dma8vY=";
      }} $out
      chmod -R u+w $out
      cp ${../../dotfiles/hammerspoon/patches/focus_watcher.lua} $out/lib/focus_watcher.lua
    '';

    # --- SketchyBar Config ---
    ".config/sketchybar/sketchybarrc" = {
      executable = true;
      source = ../../dotfiles/sketchybar/sketchybarrc;
    };
    ".config/sketchybar/colors.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/colors.sh;
    };
    ".config/sketchybar/defaults.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/defaults.sh;
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
    ".config/sketchybar/plugins/caps_lock.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/caps_lock.sh;
    };
    ".config/sketchybar/plugins/kanata.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/kanata.sh;
    };
    ".config/sketchybar/plugins/network.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/network.sh;
    };
    ".config/sketchybar/plugins/ai_agents.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/ai_agents.sh;
    };
    ".config/sketchybar/plugins/ai_agents_click.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/ai_agents_click.sh;
    };
    ".config/sketchybar/plugins/ai_agents_focus.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/ai_agents_focus.sh;
    };
    ".config/sketchybar/plugins/system_info_daemon.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/plugins/system_info_daemon.sh;
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

  home.stateVersion = "26.05";
}
