{ pkgs, lib, ... }:

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

      # Additional macOS tools
      duti # Default application handler

      # Window management
      sketchybar # Status bar

      shortcat

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

      # Docker/Colima shortcuts
      docker-start = "colima start";
      docker-stop = "colima stop";

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

    # Hammerspoon
    ".hammerspoon/init.lua".source = ../../dotfiles/hammerspoon/init.lua;
    ".hammerspoon/macos-vim-navigation/init.lua".source = ../../dotfiles/hammerspoon/macos-vim-navigation/init.lua;
    ".hammerspoon/Spoons/AClock.spoon".source = spoon "AClock" "0swzy9wvgjc93l0qc89m0zk9j0xk14w71v38vqfy2b96f4qd59p4";
    # TODO: install https://github.com/ujwalnk/GridTile
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
      text = ''
        #!/bin/bash

        # --- Theme & Colors ---
        BAR_COLOR=0xff000000       # Pure Black (Matches Notch)
        ITEM_BG_COLOR=0xff2e2e3e   # Dark Grey Pills
        ACCENT_COLOR=0xff7b5cff    # Purple Accent
        WHITE=0xffdddddd

        # --- Fonts ---
        FONT_FACE="JetBrainsMono Nerd Font"
        ICON_FONT="$FONT_FACE:Regular:16.0"
        LABEL_FONT="$FONT_FACE:Bold:13.0"

        # --- Setup Custom Events ---
        sketchybar --add event aerospace_workspace_change

        # --- Global Defaults ---
        sketchybar --default \
          updates=on \
          drawing=on \
          icon.font="$ICON_FONT" \
          label.font="$LABEL_FONT" \
          icon.color=$WHITE \
          label.color=$WHITE \
          background.height=26 \
          background.corner_radius=8 \
          label.padding_left=4 \
          label.padding_right=10 \
          icon.padding_left=10 \
          icon.padding_right=4 \
          background.padding_right=5 \
          background.padding_left=5

        # --- Bar Settings ---
        sketchybar --bar \
          height=36 \
          color=$BAR_COLOR \
          position=top \
          sticky=on \
          topmost=window \
          padding_left=10 \
          padding_right=10

        # ==============================================================================
        # LEFT SIDE
        # ==============================================================================

        # --- Front App Name (Far Left) ---
        sketchybar --add item front_app left \
                   --set front_app \
                         background.color=$ITEM_BG_COLOR \
                         icon.drawing=off \
                         label.padding_left=10 \
                         associated_display=active \
                         script="$CONFIG_DIR/plugins/front_app.sh" \
                   --subscribe front_app front_app_switched

        # --- Dynamic Workspaces ---
        for i in {1..9}; do
          sketchybar --add item space.$i left \
                     --subscribe space.$i aerospace_workspace_change \
                     --set space.$i \
                     background.color=$ITEM_BG_COLOR \
                     background.drawing=off \
                     icon=$i \
                     icon.padding_left=8 \
                     icon.padding_right=8 \
                     label.drawing=off \
                     click_script="aerospace workspace $i" \
                     script="$CONFIG_DIR/plugins/aerospace.sh $i"
        done

        # ==============================================================================
        # CENTER
        # ==============================================================================

        # --- Clock ---
        sketchybar --add item clock center \
                   --set clock \
                         update_freq=10 \
                         icon="" \
                         background.color=$ITEM_BG_COLOR \
                         background.drawing=on \
                         script="$CONFIG_DIR/plugins/clock.sh"

        # ==============================================================================
        # RIGHT SIDE
        # ==============================================================================

        # --- Volume ---
        sketchybar --add item volume right \
                   --set volume \
                         script="$CONFIG_DIR/plugins/volume.sh" \
                         background.color=$ITEM_BG_COLOR \
                         background.drawing=on \
                         updates=on \
                   --subscribe volume volume_change

        # --- Battery ---
        sketchybar --add item battery right \
                   --set battery \
                         script="$CONFIG_DIR/plugins/battery.sh" \
                         background.color=$ITEM_BG_COLOR \
                         background.drawing=on \
                         update_freq=120 \
                   --subscribe battery system_woke power_source_change

        # --- CPU ---
        sketchybar --add item cpu right \
                   --set cpu \
                         update_freq=3 \
                         icon="" \
                         background.color=$ITEM_BG_COLOR \
                         background.drawing=on \
                         script="$CONFIG_DIR/plugins/cpu.sh"

        # --- Network ---
        sketchybar --add item network right \
                   --set network \
                         update_freq=5 \
                         background.color=$ITEM_BG_COLOR \
                         background.drawing=on \
                         script="$CONFIG_DIR/plugins/network.sh"

        sketchybar --update
        echo "SketchyBar config loaded."
      '';
    };

    # --- Plugins ---

    # 1. Front App Plugin (Updates the name on the left)
    ".config/sketchybar/plugins/front_app.sh" = {
      executable = true;
      text = ''
        #!/bin/bash
        if [ "$SENDER" = "front_app_switched" ]; then
          sketchybar --set $NAME label="$INFO"
        fi
      '';
    };

    # 2. AeroSpace Plugin (Handles visibility & highlighting)
    ".config/sketchybar/plugins/aerospace.sh" = {
      executable = true;
      text = ''
        #!/bin/bash

        # FIX: Add NixOS/nix-darwin system paths so we can find 'aerospace'
        export PATH=$PATH:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:/opt/homebrew/bin:/usr/local/bin

        # Fallback: If event didn't pass the variable, query it manually
        if [ -z "$FOCUSED_WORKSPACE" ]; then
            FOCUSED_WORKSPACE=$(aerospace list-workspaces --focused)
        fi

        # 1. Highlight Active Workspace
        if [ "$1" = "$FOCUSED_WORKSPACE" ]; then
            sketchybar --set $NAME background.drawing=on background.color=0xff7b5cff icon.color=0xffffffff
        else
            sketchybar --set $NAME background.drawing=off icon.color=0xffdddddd
        fi

        # 2. Auto-Hide Empty Workspaces
        OCCUPIED_SPACES=$(aerospace list-windows --all --format '%{workspace}')

        if [[ $OCCUPIED_SPACES == *"$1"* ]] || [ "$1" = "$FOCUSED_WORKSPACE" ]; then
            sketchybar --set $NAME drawing=on
        else
            sketchybar --set $NAME drawing=off
        fi
      '';
    };

    # 3. Clock Plugin
    ".config/sketchybar/plugins/clock.sh" = {
      executable = true;
      text = ''
        #!/bin/bash
        sketchybar --set $NAME label="$(date '+%H:%M')"
      '';
    };

    # 4. Volume Plugin
    ".config/sketchybar/plugins/volume.sh" = {
      executable = true;
      text = ''
        #!/bin/bash
        VOL=$(osascript -e "output volume of (get volume settings)")
        MUTED=$(osascript -e "output muted of (get volume settings)")

        if [[ $MUTED != "false" ]]; then
          ICON=""
        else
          case $VOL in
            [6-9][0-9]|100) ICON="";;
            [3-5][0-9]) ICON="";;
            *) ICON=""
          esac
        fi
        sketchybar --set $NAME icon="$ICON" label="$VOL%"
      '';
    };

    # 5. CPU Plugin
    ".config/sketchybar/plugins/cpu.sh" = {
      executable = true;
      text = ''
        #!/bin/bash

        # 1. Run top for 2 samples (-l 2) because sample 1 is usually invalid.
        # 2. Grep for the CPU usage line.
        # 3. Tail -1 to get the second (accurate) sample.
        # 4. Awk columns 3 (User) and 5 (Sys) to get total load.
        #    (Output format is usually: CPU usage: 12% user, 10% sys, 78% idle)

        CPU_LOAD=$(top -l 2 | grep -E "^CPU" | tail -1 | awk '{ print $3 + $5 }')

        # Remove decimal points for a clean integer
        CPU_INT=''${CPU_LOAD%.*}

        sketchybar --set $NAME label="$CPU_INT%"
      '';
    };

    # 6. Battery Plugin
    ".config/sketchybar/plugins/battery.sh" = {
      executable = true;
      text = ''
        #!/bin/bash
        PERCENTAGE=$(pmset -g batt | grep -o "[0-9]\{1,3\}%" | tr -d "%")
        CHARGING=$(pmset -g batt | grep 'AC Power')
        if [ "$PERCENTAGE" = "" ]; then exit 0; fi

        case ''${PERCENTAGE} in
          9[0-9]|100) ICON="" ;;
          [6-8][0-9]) ICON="" ;;
          [3-5][0-9]) ICON="" ;;
          [1-2][0-9]) ICON="" ;;
          *) ICON=""
        esac
        if [[ $CHARGING != "" ]]; then ICON=""; fi
        sketchybar --set $NAME icon="$ICON" label="''${PERCENTAGE}%"
      '';
    };

    # 7. Network Plugin
    ".config/sketchybar/plugins/network.sh" = {
      executable = true;
      text = ''
        #!/bin/bash
        WIFI=$(ipconfig getsummary en0 | awk -F ' SSID : '  '/ SSID : / {print $2}')
        if [ "$WIFI" = "" ]; then
           sketchybar --set $NAME label="Disconnected" icon="󰤠"
        else
           sketchybar --set $NAME label="$WIFI" icon="󰤢"
        fi
      '';
    };
  };

  # macOS-specific environment variables
  home.sessionVariables = {
    # macOS-specific environment
    BROWSER = "open";
  };

  home.stateVersion = "25.11";
}
