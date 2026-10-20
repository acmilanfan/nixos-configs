{ pkgs, lib, unstable, inputs, ... }:

let
  sketchybarReload = ''
    sb="/etc/profiles/per-user/$(id -un)/bin/sketchybar"
    if [ -x "$sb" ] && /usr/bin/pgrep -x sketchybar >/dev/null; then
      run "$sb" --reload || true
    fi
  '';
  # Pinned to commits, not master: a fixed hash on a moving URL breaks the build on any
  # re-fetch after upstream changes (GC, a fresh machine, the other host).
  spoonsRev = "5cbfe7d95bc58fd46e94d9904160acaa8acd22bd";
  spoon =
    name: sha256:
    pkgs.fetchzip {
      url = "https://github.com/Hammerspoon/Spoons/raw/${spoonsRev}/Spoons/${name}.spoon.zip";
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

      # Required by the Vicinae fuzzy-files extension, which spawns `gf`
      # (https://github.com/sameoldlab/goldfish). The published v0.1.0 macOS
      # release binary prints nothing; build from source instead.
      inputs.goldfish.packages.${pkgs.stdenv.hostPlatform.system}.goldfish

      # Update the pinned Raycast Store extensions in this repo
      # (see nixos/home-manager/common/vicinae.nix). Reads the repo via
      # $VICINAE_CONFIG_ROOT or ~/configs/nixos-configs.
      (pkgs.writeShellScriptBin "update-vicinae-raycast-extensions"
        (lib.readFile ../../scripts/update-vicinae-raycast-extensions.sh)
      )

      # Toggle pair for Vicinae. State is preserved across closes by default
      # (pop_to_root_on_close = false), so:
      #   vicinae-toggle-reset   — toggle, reset to the root search on open
      #   vicinae-toggle-preserve — toggle, keep whatever view it was on
      (pkgs.writeShellScriptBin "vicinae-toggle-reset" ''
        if /opt/homebrew/bin/vicinae state open >/dev/null 2>&1; then
          /opt/homebrew/bin/vicinae 'vicinae://close'
        else
          /opt/homebrew/bin/vicinae 'vicinae://open?popToRoot=true'
        fi
      '')

      # Toggle the Vicinae window while preserving whatever view it was on
      # (plain `vicinae toggle` can land on the root search again).
      (pkgs.writeShellScriptBin "vicinae-toggle-preserve" ''
        if /opt/homebrew/bin/vicinae state open >/dev/null 2>&1; then
          /opt/homebrew/bin/vicinae 'vicinae://close?popToRootType=suspended&clearRootSearch=false'
        else
          /opt/homebrew/bin/vicinae 'vicinae://open'
        fi
      '')

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
      # Nvim scratchpad: bare `nvim` (not a store path) so the configured
      # programs.neovim wrapper + orgmode is used. Copies to clipboard on
      # :wq; :cq exits non-zero so pbcopy is skipped and clipboard is untouched.
      # Runs from a dedicated empty dir: orgmode's org_agenda_files globs
      # "$cwd/**/*.org" recursively, and GUI-launched (via `open`) processes
      # start with cwd "/" -- without this cd it walks the whole filesystem.
      (pkgs.writeShellScriptBin "nvim-scratchpad" ''
        # Per-user $TMPDIR (/var/folders/...), not a shared /tmp path.
        SCRATCH_DIR="''${TMPDIR:-$HOME/.cache}/nvim-scratchpad"
        SCRATCH_FILE="$SCRATCH_DIR/nvim_scratch.org"
        mkdir -p "$SCRATCH_DIR"
        : > "$SCRATCH_FILE"
        cd "$SCRATCH_DIR"
        nvim -c 'startinsert' "$SCRATCH_FILE" && /usr/bin/pbcopy < "$SCRATCH_FILE"
      '')

      (pkgs.writeShellApplication {
        name = "create-utm-vm-hyprland";
        runtimeInputs = [ pkgs.qemu-utils ];
        text = lib.readFile ../vm-hyprland/scripts/create-utm-vm.sh;
      })

      # Point an existing UTM VM's VirtFS share at a folder (UTM keeps it in
      # its registry, not config.plist, so it can't be set declaratively).
      # Takes effect on the VM's next start.
      (pkgs.writeShellApplication {
        name = "utm-vm-hyprland-share";
        text = ''
          vm=''${1:-vm-hyprland}
          dir=''${2:-$HOME/configs/nixos-configs}
          osascript - "$vm" "$dir" <<'APPLESCRIPT'
          on run argv
            tell application "UTM"
              set vm to virtual machine named (item 1 of argv)
              update registry of vm with {POSIX file (item 2 of argv)}
              return registry of vm
            end tell
          end run
          APPLESCRIPT
        '';
      })

      # Remote-deploy config changes to the vm-hyprland UTM VM: build here
      # (the local daemon hands aarch64-linux to nix.linux-builder) and
      # push+activate over SSH, without touching the VM's own clone. Target
      # user must be gentooway (the only user vm-hyprland's own config
      # defines) - without it ssh silently falls back to the local macOS
      # username, which can never authenticate. A script, not an alias: an
      # alias expands ${VM_HYPRLAND_HOST} before a `VM_HYPRLAND_HOST=<ip>
      # sup-vm-hyprland` prefix applies, so the override never took effect.
      # No --build-host localhost: it made nixos-rebuild copy from
      # ssh://localhost, needing Remote Login and the Mac password.
      (pkgs.writeShellScriptBin "sup-vm-hyprland" ''
        exec nixos-rebuild switch \
          --flake "$HOME/configs/nixos-configs#vm-hyprland" \
          --target-host "gentooway@''${VM_HYPRLAND_HOST:-vm-hyprland}" \
          --sudo --ask-sudo-password "$@"
      '')

      # Feed Raycast OAuth callbacks (https://www.raycast.com/redirect?...)
      # to Vicinae. Raycast's scheme is owned by the Raycast app, so the
      # browser redirect can't reach Vicinae directly; run this after the
      # browser shows "Connected to ..." while the Vicinae overlay is waiting.
      (pkgs.writeShellScriptBin "vicinae-oauth" (lib.readFile ./scripts/vicinae-oauth))
      # Place the external screen above/left/right of the MacBook screen via displayplacer
      # (Homebrew, darwin/common.nix), resolving screen ids at run time.
      (pkgs.writeShellScriptBin "display-arrange" (lib.readFile ./scripts/display-arrange))
      # New window in the running Ghostty instead of another Ghostty process (one Dock tile).
      (pkgs.writeShellScriptBin "ghostty-window" (lib.readFile ./scripts/ghostty-window))
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [
      # Darwin-specific packages
    ];

  # macOS-specific shell aliases
  programs.zsh.shellAliases = pkgs.lib.mkMerge [
    {
      # macOS-specific aliases
      sup = "sudo darwin-rebuild switch --flake $HOME/configs/nixos-configs";

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

      # Clipboard is handled by Vicinae; open its clipboard history view
      # (deeplink: https://docs.vicinae.com/deeplinks).
      clipboard-history = "vicinae 'vicinae://launch/clipboard/history'";
      clipboard-clear = "vicinae cmd launch clipboard:clear-history";

      # Kanata configuration management
      reload-kanata = "~/.config/kanata/reload-kanata.sh";
      switch-kanata = "~/.config/kanata/switch-kanata.sh";
      reload-kanata-logs = "~/.config/kanata/reload-kanata.sh --show-logs";

      # Sync Dashboard
      syncmon = "ghostty-window --title 'SyncMon Dashboard' syncmon";
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

    # Paths need adjustment to point to dotfiles relative to this new location
    # nixos/common/home-darwin.nix -> ../../dotfiles is correct if nixos/common is at same level as nixos/mac-work
    # dotfiles is in root/dotfiles.
    # root/nixos/common/home-darwin.nix
    # root/dotfiles
    # so ../../dotfiles is correct.

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

    # ~/.syncmon.yaml is rendered by sops-nix (../home-manager/common/sops.nix)
    # so the Syncthing API key stays out of /nix/store.

    # Hammerspoon: everything under dotfiles/hammerspoon (init.lua, nanowm/*,
    # macos-vim-navigation, ...), so a new module can't be forgotten here.
    # recursive = true links file by file: ~/.hammerspoon stays a real,
    # writable directory for NanoWM's nanowm_state.json, nanowm_slow.log and
    # nanowm_spec_report.txt, and for the Spoons linked below.
    ".hammerspoon" = {
      source = builtins.path {
        name = "hammerspoon-config";
        path = ../../dotfiles/hammerspoon;
        filter = path: _type: baseNameOf path != ".DS_Store";
      };
      recursive = true;
    };

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
      cp -r ${inputs.vimmode-spoon} $out
      chmod -R u+w $out
      cp ${../../dotfiles/hammerspoon/patches/focus_watcher.lua} $out/lib/focus_watcher.lua
    '';

    # --- SketchyBar Config ---
    # A running sketchybar keeps the config it started with; reload it when that changes.
    # (Plugin scripts are re-read on every run and need no reload.)
    ".config/sketchybar/sketchybarrc" = {
      executable = true;
      source = ../../dotfiles/sketchybar/sketchybarrc;
      onChange = sketchybarReload;
    };
    ".config/sketchybar/colors.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/colors.sh;
      onChange = sketchybarReload;
    };
    ".config/sketchybar/defaults.sh" = {
      executable = true;
      source = ../../dotfiles/sketchybar/defaults.sh;
      onChange = sketchybarReload;
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

  # Reload Hammerspoon when a rebuild changed any of its files. Nothing else does: the
  # darwin-startup reload only runs when Hammerspoon wasn't running, so a running instance
  # kept the old config after every switch. Compares a hash of ~/.hammerspoon's Lua files
  # (spoons included) with the one from the last switch, so it reloads once, and only on change.
  home.activation.reloadHammerspoon = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    stamp="$HOME/.cache/hammerspoon-config.sha"
    new=$(/usr/bin/find -L "$HOME/.hammerspoon" -name '*.lua' -type f -print0 2>/dev/null \
      | /usr/bin/sort -z | /usr/bin/xargs -0 /bin/cat 2>/dev/null | /usr/bin/shasum | /usr/bin/cut -c1-40)
    old=$(/bin/cat "$stamp" 2>/dev/null || true)
    if [ "$new" != "$old" ]; then
      if /usr/bin/pgrep -x Hammerspoon >/dev/null; then
        run /usr/bin/open -g "hammerspoon://reload" || true
      fi
      run /bin/mkdir -p "$HOME/.cache"
      [[ -v DRY_RUN ]] || echo "$new" > "$stamp"
    fi
  '';

  home.stateVersion = "26.05";
}
