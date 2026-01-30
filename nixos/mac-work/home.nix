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
      nowplaying-cli # Media info for sketchybar

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

        # ═══════════════════════════════════════════════════════════════════════════
        # SKETCHYBAR CONFIG - Clean & Informative
        # ═══════════════════════════════════════════════════════════════════════════

        # --- Theme & Colors ---
        # BAR_COLOR=0xff1a1b26        # Tokyo Night background
        # ITEM_BG_COLOR=0xff2e2e3e   # Dark Grey Pills
        # ACCENT_COLOR=0xff7aa2f7     # Blue accent
        BAR_COLOR=0xff000000       # Pure Black (Matches Notch)
        ITEM_BG_COLOR=0xff24283b    # Slightly lighter for pills
        ACCENT_COLOR=0xff7b5cff    # Purple Accent
        ACCENT_SECONDARY=0xff9ece6a # Green accent
        WARNING_COLOR=0xffe0af68    # Yellow/Orange warning
        CRITICAL_COLOR=0xfff7768e   # Red critical
        INACTIVE_COLOR=0xff565f89   # Muted grey
        WHITE=0xffc0caf5            # Soft white
        DIM=0xff565f89              # Dimmed text

        # --- Fonts ---
        FONT_FACE="JetBrainsMono Nerd Font"
        ICON_FONT="$FONT_FACE:Regular:14.0"
        LABEL_FONT="$FONT_FACE:Medium:11.0"
        LABEL_FONT_BOLD="$FONT_FACE:Bold:11.0"

        # --- Setup Custom Events ---
        sketchybar --add event nanowm_update

        # --- Global Defaults ---
        sketchybar --default \
          updates=on \
          drawing=on \
          icon.font="$ICON_FONT" \
          label.font="$LABEL_FONT" \
          icon.color=$WHITE \
          label.color=$WHITE \
          background.height=22 \
          background.corner_radius=6 \
          label.padding_left=4 \
          label.padding_right=6 \
          icon.padding_left=6 \
          icon.padding_right=4 \
          background.padding_right=2 \
          background.padding_left=2

        # --- Bar Settings ---
        sketchybar --bar \
          height=32 \
          color=$BAR_COLOR \
          position=top \
          sticky=on \
          topmost=window \
          padding_left=6 \
          padding_right=6 \
          shadow=on

        # ═══════════════════════════════════════════════════════════════════════════
        # LEFT SIDE - Workspaces, Timer & App
        # ═══════════════════════════════════════════════════════════════════════════

        # --- Workspace Items (1-10 + Special) ---
        for i in 1 2 3 4 5 6 7 8 9 10 S; do
          sketchybar --add item space.$i left \
                     --set space.$i \
                           icon="$i" \
                           icon.font="$FONT_FACE:Bold:11.0" \
                           icon.padding_left=8 \
                           icon.padding_right=8 \
                           background.color=$INACTIVE_COLOR \
                           background.drawing=off \
                           label.drawing=off \
                           drawing=off \
                           click_script="$CONFIG_DIR/plugins/space_click.sh" \
                           script="$CONFIG_DIR/plugins/space.sh" \
                     --subscribe space.$i nanowm_update mouse.clicked
        done

        # --- Separator (between tags and timer) ---
        sketchybar --add item sep_tags left \
                   --set sep_tags \
                         icon="│" \
                         icon.color=$INACTIVE_COLOR \
                         icon.font="$FONT_FACE:Regular:12.0" \
                         icon.padding_left=6 \
                         icon.padding_right=6 \
                         background.drawing=off \
                         label.drawing=off

        # --- NanoWM Timer (shows only when active) ---
        sketchybar --add item nanowm_timer left \
                   --set nanowm_timer \
                         background.color=0xff3d5a80 \
                         background.drawing=off \
                         icon="󰔟" \
                         icon.color=$WARNING_COLOR \
                         icon.padding_left=8 \
                         icon.padding_right=4 \
                         label="" \
                         label.padding_left=4 \
                         label.padding_right=8 \
                         drawing=off \
                         script="$CONFIG_DIR/plugins/nanowm_timer.sh" \
                   --subscribe nanowm_timer nanowm_update

        # --- Separator (between timer and front_app, conditional) ---
        sketchybar --add item sep_timer left \
                   --set sep_timer \
                         icon="│" \
                         icon.color=$INACTIVE_COLOR \
                         icon.font="$FONT_FACE:Regular:12.0" \
                         icon.padding_left=6 \
                         icon.padding_right=6 \
                         background.drawing=off \
                         label.drawing=off \
                         drawing=off \
                         script="$CONFIG_DIR/plugins/sep_timer.sh" \
                   --subscribe sep_timer nanowm_update

        # --- Front App Icon + Name ---
        sketchybar --add item front_app left \
                   --set front_app \
                         background.color=$ITEM_BG_COLOR \
                         background.drawing=on \
                         icon.drawing=on \
                         icon.font="sketchybar-app-font:Regular:14.0" \
                         label.font="$LABEL_FONT_BOLD" \
                         label.padding_left=4 \
                         label.padding_right=8 \
                         icon.padding_left=8 \
                         script="$CONFIG_DIR/plugins/front_app.sh" \
                   --subscribe front_app front_app_switched

        # ═══════════════════════════════════════════════════════════════════════════
        # CENTER - Date & Time
        # ═══════════════════════════════════════════════════════════════════════════

        sketchybar --add item date center \
                   --set date \
                         update_freq=60 \
                         icon="󰃭" \
                         icon.color=$ACCENT_COLOR \
                         background.drawing=off \
                         script="$CONFIG_DIR/plugins/date.sh"

        sketchybar --add item clock center \
                   --set clock \
                         update_freq=10 \
                         icon="󰥔" \
                         icon.color=$ACCENT_SECONDARY \
                         background.drawing=off \
                         script="$CONFIG_DIR/plugins/clock.sh"

        # ═══════════════════════════════════════════════════════════════════════════
        # RIGHT SIDE - System Info
        # ═══════════════════════════════════════════════════════════════════════════

        # --- Date & Time (Rightmost) ---
        sketchybar --add item datetime right \
                   --set datetime \
                         icon="󰃭" \
                         icon.color=$ACCENT_COLOR \
                         background.color=$ITEM_BG_COLOR \
                         background.drawing=on \
                         update_freq=30 \
                         script="$CONFIG_DIR/plugins/datetime.sh"

        # --- Separator ---
        sketchybar --add item sep_right0 right \
                   --set sep_right0 \
                         icon="│" \
                         icon.color=$INACTIVE_COLOR \
                         icon.font="$FONT_FACE:Regular:12.0" \
                         icon.padding_left=4 \
                         icon.padding_right=4 \
                         background.drawing=off \
                         label.drawing=off

        # --- Media (Now Playing) ---
        sketchybar --add item media right \
                   --set media \
                         icon="󰎆" \
                         icon.color=$ACCENT_COLOR \
                         label.max_chars=30 \
                         scroll_texts=on \
                         background.color=$ITEM_BG_COLOR \
                         background.drawing=on \
                         script="$CONFIG_DIR/plugins/media.sh" \
                         update_freq=5 \
                   --subscribe media media_change

        # --- Separator (between network and media, conditional on media playing) ---
        sketchybar --add item sep_media right \
                   --set sep_media \
                         icon="│" \
                         icon.color=$INACTIVE_COLOR \
                         icon.font="$FONT_FACE:Regular:12.0" \
                         icon.padding_left=4 \
                         icon.padding_right=4 \
                         background.drawing=off \
                         label.drawing=off \
                         drawing=off \
                         script="$CONFIG_DIR/plugins/sep_media.sh" \
                         update_freq=5

        # --- Network (WiFi/Ethernet) ---
        sketchybar --add item network right \
                   --set network \
                         icon="󰤨" \
                         icon.color=$ACCENT_SECONDARY \
                         background.color=$ITEM_BG_COLOR \
                         background.drawing=on \
                         script="$CONFIG_DIR/plugins/network.sh" \
                         update_freq=10 \
                   --subscribe network wifi_change

        # --- CPU Graph ---
        sketchybar --add graph cpu_graph right 50 \
                   --set cpu_graph \
                         graph.color=$ACCENT_COLOR \
                         graph.fill_color=0x407aa2f7 \
                         graph.line_width=1 \
                         background.color=$ITEM_BG_COLOR \
                         background.drawing=on \
                         background.height=22 \
                         background.corner_radius=6 \
                         icon="󰻠" \
                         icon.color=$ACCENT_COLOR \
                         icon.padding_left=6 \
                         label.padding_right=6 \
                         update_freq=2 \
                         script="$CONFIG_DIR/plugins/cpu_graph.sh"

        # --- Memory Usage ---
        sketchybar --add item memory right \
                   --set memory \
                         icon="󰍛" \
                         icon.color=$WARNING_COLOR \
                         background.color=$ITEM_BG_COLOR \
                         background.drawing=on \
                         update_freq=5 \
                         script="$CONFIG_DIR/plugins/memory.sh"

        # --- Volume ---
        sketchybar --add item volume right \
                   --set volume \
                         icon="󰕾" \
                         background.color=$ITEM_BG_COLOR \
                         background.drawing=on \
                         script="$CONFIG_DIR/plugins/volume.sh" \
                   --subscribe volume volume_change

        # --- Battery ---
        sketchybar --add item battery right \
                   --set battery \
                         icon="󰁹" \
                         background.color=$ITEM_BG_COLOR \
                         background.drawing=on \
                         update_freq=60 \
                         script="$CONFIG_DIR/plugins/battery.sh" \
                   --subscribe battery system_woke power_source_change

        sketchybar --update
        echo "SketchyBar config loaded."
      '';
    };

    # --- Plugins ---

    # Space Click Plugin (handles clicking on workspaces)
    ".config/sketchybar/plugins/space_click.sh" = {
      executable = true;
      text = ''
        #!/bin/bash

        # Extract space number from item name (space.1 -> 1, space.S -> S)
        SPACE_ID=$(echo "$NAME" | cut -d. -f2)

        # Use hs CLI to switch to the workspace
        if [ "$SPACE_ID" = "S" ]; then
          /opt/homebrew/bin/hs -c "NanoWM.toggleSpecial()"
        else
          /opt/homebrew/bin/hs -c "NanoWM.gotoTag($SPACE_ID)"
        fi
      '';
    };

    # Space/Workspace Plugin
    ".config/sketchybar/plugins/space.sh" = {
      executable = true;
      text = ''
        #!/bin/bash

        # Extract space number from item name (space.1 -> 1, space.S -> S)
        SPACE_ID=$(echo "$NAME" | cut -d. -f2)

        if [ "$SENDER" = "nanowm_update" ]; then
          IS_ACTIVE=false
          HAS_WINDOWS=false
          IS_URGENT=false

          # Check if this space is the current tag
          if [ "$TAG" = "$SPACE_ID" ]; then
            IS_ACTIVE=true
          fi

          # Check if this space has windows (is in OCCUPIED list)
          for occupied in $OCCUPIED; do
            if [ "$occupied" = "$SPACE_ID" ]; then
              HAS_WINDOWS=true
              break
            fi
          done

          # Check if this space is urgent
          for urgent in $URGENT; do
            if [ "$urgent" = "$SPACE_ID" ]; then
              IS_URGENT=true
              break
            fi
          done

          if [ "$IS_ACTIVE" = true ]; then
            # Current workspace - highlighted blue
            sketchybar --set "$NAME" drawing=on background.drawing=on background.color=0xff7aa2f7 icon.color=0xff1a1b26
          elif [ "$IS_URGENT" = true ]; then
            # Urgent workspace - highlighted red/orange (attention needed!)
            sketchybar --set "$NAME" drawing=on background.drawing=on background.color=0xfff7768e icon.color=0xff1a1b26
          elif [ "$HAS_WINDOWS" = true ]; then
            # Has windows but not active - visible but dimmed
            sketchybar --set "$NAME" drawing=on background.drawing=on background.color=0xff3b4261 icon.color=0xffc0caf5
          else
            # Empty workspace - hidden
            sketchybar --set "$NAME" drawing=off
          fi
        fi
      '';
    };

    # Front App Plugin
    ".config/sketchybar/plugins/front_app.sh" = {
      executable = true;
      text = ''
        #!/bin/bash
        if [ "$SENDER" = "front_app_switched" ]; then
          sketchybar --set $NAME label="$INFO" icon.background.image="app.$INFO"
        fi
      '';
    };

    # NanoWM Timer Plugin
    ".config/sketchybar/plugins/nanowm_timer.sh" = {
      executable = true;
      text = ''
        #!/bin/bash

        if [ "$SENDER" = "nanowm_update" ]; then
          if [ -n "$TIMER" ] && [ "$TIMER" != "" ]; then
            sketchybar --set $NAME drawing=on background.drawing=on label="$TIMER"
          else
            sketchybar --set $NAME drawing=off background.drawing=off
          fi
        fi
      '';
    };

    # Separator between timer and front_app (only shows when timer is active)
    ".config/sketchybar/plugins/sep_timer.sh" = {
      executable = true;
      text = ''
        #!/bin/bash

        if [ "$SENDER" = "nanowm_update" ]; then
          if [ -n "$TIMER" ] && [ "$TIMER" != "" ]; then
            sketchybar --set $NAME drawing=on
          else
            sketchybar --set $NAME drawing=off
          fi
        fi
      '';
    };

    # Date Plugin
    ".config/sketchybar/plugins/date.sh" = {
      executable = true;
      text = ''
        #!/bin/bash
        sketchybar --set $NAME label="$(date '+%a %d %b')"
      '';
    };

    # Clock Plugin
    ".config/sketchybar/plugins/clock.sh" = {
      executable = true;
      text = ''
        #!/bin/bash
        sketchybar --set $NAME label="$(date '+%H:%M')"
      '';
    };

    # Volume Plugin
    ".config/sketchybar/plugins/volume.sh" = {
      executable = true;
      text = ''
        #!/bin/bash
        VOL=$(osascript -e "output volume of (get volume settings)")
        MUTED=$(osascript -e "output muted of (get volume settings)")

        if [[ $MUTED != "false" ]]; then
          ICON="󰝟"
          COLOR="0xff565f89"
        elif [[ $VOL -ge 66 ]]; then
          ICON="󰕾"
          COLOR="0xff7aa2f7"
        elif [[ $VOL -ge 33 ]]; then
          ICON="󰖀"
          COLOR="0xff7aa2f7"
        elif [[ $VOL -ge 1 ]]; then
          ICON="󰕿"
          COLOR="0xff7aa2f7"
        else
          ICON="󰝟"
          COLOR="0xff565f89"
        fi
        sketchybar --set $NAME icon="$ICON" icon.color="$COLOR" label="$VOL%"
      '';
    };

    # CPU Plugin
    # DateTime Plugin (Right side - day and time)
    ".config/sketchybar/plugins/datetime.sh" = {
      executable = true;
      text = ''
        #!/bin/bash
        # Format: "Mon 14:30"
        DAY=$(date '+%a')
        TIME=$(date '+%H:%M')
        sketchybar --set $NAME label="$DAY $TIME"
      '';
    };

    ".config/sketchybar/plugins/cpu_graph.sh" = {
      executable = true;
      text = ''
        #!/bin/bash
        # Get CPU usage - faster method using iostat
        CPU_LOAD=$(iostat -c 2 disk0 | tail -1 | awk '{print 100 - $6}' | cut -d. -f1)

        # Fallback to top if iostat fails
        if [ -z "$CPU_LOAD" ] || [ "$CPU_LOAD" -lt 0 ] 2>/dev/null; then
          CPU_LOAD=$(top -l 1 -n 0 | grep -E "^CPU" | awk '{ print int($3 + $5) }')
        fi

        # Ensure we have a valid number
        if [ -z "$CPU_LOAD" ]; then
          CPU_LOAD=0
        fi

        # Color based on load
        if [[ $CPU_LOAD -ge 80 ]]; then
          COLOR="0xfff7768e"  # Critical red
        elif [[ $CPU_LOAD -ge 50 ]]; then
          COLOR="0xffe0af68"  # Warning yellow
        else
          COLOR="0xff7aa2f7"  # Normal blue
        fi

        # Push value to graph (0.0 to 1.0 scale) and update label
        sketchybar --push cpu_graph $(echo "scale=2; $CPU_LOAD / 100" | bc) \
                   --set cpu_graph label="$CPU_LOAD%" icon.color="$COLOR"
      '';
    };

    # Memory Plugin
    ".config/sketchybar/plugins/memory.sh" = {
      executable = true;
      text = ''
        #!/bin/bash
        # Get memory pressure (percentage of memory used)
        MEMORY=$(memory_pressure 2>/dev/null | grep "System-wide memory free percentage" | awk '{print 100 - $5}' | tr -d '%')

        # Fallback if memory_pressure doesn't work
        if [ -z "$MEMORY" ]; then
          # Use vm_stat as fallback
          PAGES_FREE=$(vm_stat | grep "Pages free" | awk '{print $3}' | tr -d '.')
          PAGES_ACTIVE=$(vm_stat | grep "Pages active" | awk '{print $3}' | tr -d '.')
          PAGES_INACTIVE=$(vm_stat | grep "Pages inactive" | awk '{print $3}' | tr -d '.')
          PAGES_WIRED=$(vm_stat | grep "Pages wired" | awk '{print $4}' | tr -d '.')
          PAGES_COMPRESSED=$(vm_stat | grep "Pages occupied by compressor" | awk '{print $5}' | tr -d '.')

          TOTAL=$((PAGES_FREE + PAGES_ACTIVE + PAGES_INACTIVE + PAGES_WIRED + PAGES_COMPRESSED))
          USED=$((PAGES_ACTIVE + PAGES_WIRED + PAGES_COMPRESSED))

          if [ $TOTAL -gt 0 ]; then
            MEMORY=$((USED * 100 / TOTAL))
          else
            MEMORY=0
          fi
        fi

        if [[ $MEMORY -ge 80 ]]; then
          COLOR="0xfff7768e"  # Critical red
        elif [[ $MEMORY -ge 60 ]]; then
          COLOR="0xffe0af68"  # Warning yellow
        else
          COLOR="0xff9ece6a"  # Normal green
        fi

        sketchybar --set $NAME label="$MEMORY%" icon.color="$COLOR"
      '';
    };

    # Battery Plugin
    ".config/sketchybar/plugins/battery.sh" = {
      executable = true;
      text = ''
        #!/bin/bash
        PERCENTAGE=$(pmset -g batt | grep -o "[0-9]\{1,3\}%" | tr -d "%")
        CHARGING=$(pmset -g batt | grep 'AC Power')

        if [ "$PERCENTAGE" = "" ]; then exit 0; fi

        if [[ $CHARGING != "" ]]; then
          ICON="󰂄"
          COLOR="0xff9ece6a"  # Green when charging
        elif [[ $PERCENTAGE -ge 80 ]]; then
          ICON="󰁹"
          COLOR="0xff9ece6a"  # Green
        elif [[ $PERCENTAGE -ge 60 ]]; then
          ICON="󰂁"
          COLOR="0xff7aa2f7"  # Blue
        elif [[ $PERCENTAGE -ge 40 ]]; then
          ICON="󰁿"
          COLOR="0xff7aa2f7"  # Blue
        elif [[ $PERCENTAGE -ge 20 ]]; then
          ICON="󰁻"
          COLOR="0xffe0af68"  # Yellow warning
        else
          ICON="󰂃"
          COLOR="0xfff7768e"  # Red critical
        fi

        sketchybar --set $NAME icon="$ICON" icon.color="$COLOR" label="$PERCENTAGE%"
      '';
    };

    # Network Plugin - Icon only with signal strength
    ".config/sketchybar/plugins/network.sh" = {
      executable = true;
      text = ''
        #!/bin/bash
        # Use system_profiler to get WiFi signal strength (works on all macOS versions)
        SIGNAL_INFO=$(system_profiler SPAirPortDataType 2>/dev/null | grep "Signal / Noise" | head -1)
        
        if [ -n "$SIGNAL_INFO" ]; then
          # Extract signal strength (e.g., "-55 dBm")
          RSSI=$(echo "$SIGNAL_INFO" | sed 's/.*: /' | cut -d' ' -f1)
          
          if [ -n "$RSSI" ] && [ "$RSSI" -lt 0 ] 2>/dev/null; then
            # WiFi is connected - show signal strength icon and value
            if [[ $RSSI -ge -50 ]]; then
              ICON="󰤨"  # Excellent (4 bars)
              COLOR="0xff9ece6a"
            elif [[ $RSSI -ge -60 ]]; then
              ICON="󰤥"  # Good (3 bars)
              COLOR="0xff7aa2f7"
            elif [[ $RSSI -ge -70 ]]; then
              ICON="󰤢"  # Fair (2 bars)
              COLOR="0xffe0af68"
            else
              ICON="󰤟"  # Weak (1 bar)
              COLOR="0xfff7768e"
            fi
            sketchybar --set $NAME icon="$ICON" icon.color="$COLOR" label="$RSSI"
            exit 0
          fi
        fi
        
        # Fallback: Check if connected via scutil
        NETWORK_STATUS=$(scutil --nwi 2>/dev/null | grep "IPv4 network interface" -A1 | grep "en0")
        if [ -n "$NETWORK_STATUS" ]; then
          # Connected but could not get signal strength
          sketchybar --set $NAME icon="󰤨" icon.color="0xff9ece6a" label=""
          exit 0
        fi
        
        # Check for ethernet on various interfaces
        for iface in en1 en2 en3 en4 en5 en6; do
          ETHERNET=$(ifconfig $iface 2>/dev/null | grep "status: active")
          if [ -n "$ETHERNET" ]; then
            sketchybar --set $NAME icon="󰈀" icon.color="0xff9ece6a" label="ETH"
            exit 0
          fi
        done
        
        # Check if WiFi is on but not connected
        WIFI_POWER=$(networksetup -getairportpower en0 2>/dev/null | grep "On")
        if [ -n "$WIFI_POWER" ]; then
          sketchybar --set $NAME icon="󰤯" icon.color="0xff565f89" label=""
        else
          sketchybar --set $NAME icon="󰤭" icon.color="0xff565f89" label=""
        fi
      '';
    };
    ".config/sketchybar/plugins/sep_media.sh" = {
      executable = true;
      text = ''
        #!/bin/bash
        # Check if any media is playing by looking at the Now Playing info
        NOW_PLAYING=$(nowplaying-cli get title 2>/dev/null)
        
        if [ -n "$NOW_PLAYING" ] && [ "$NOW_PLAYING" != "null" ]; then
          sketchybar --set $NAME drawing=on
        else
          sketchybar --set $NAME drawing=off
        fi
      '';
    };

    # Media Plugin (Now Playing) - supports Spotify, Music, and browser media
    ".config/sketchybar/plugins/media.sh" = {
      executable = true;
      text = ''
        #!/bin/bash

        # Use nowplaying-cli if available (detects all media including browser)
        if command -v nowplaying-cli &> /dev/null; then
          TITLE=$(nowplaying-cli get title 2>/dev/null)
          ARTIST=$(nowplaying-cli get artist 2>/dev/null)
          APP=$(nowplaying-cli get appBundleIdentifier 2>/dev/null)
          
          if [ -n "$TITLE" ] && [ "$TITLE" != "null" ] && [ "$TITLE" != "" ]; then
            # Determine icon based on app
            case "$APP" in
              *spotify*)
                ICON="󰓇"
                COLOR="0xff1db954"
                ;;
              *music*|*itunes*)
                ICON="󰎆"
                COLOR="0xfffc3c44"
                ;;
              *firefox*)
                ICON="󰈹"
                COLOR="0xffff7139"
                ;;
              *chrome*|*chromium*)
                ICON="󰊯"
                COLOR="0xff4285f4"
                ;;
              *safari*)
                ICON="󰀹"
                COLOR="0xff006cff"
                ;;
              *)
                ICON="󰎆"
                COLOR="0xff7aa2f7"
                ;;
            esac
            
            # Format label
            if [ -n "$ARTIST" ] && [ "$ARTIST" != "null" ] && [ "$ARTIST" != "" ]; then
              LABEL="$ARTIST - $TITLE"
            else
              LABEL="$TITLE"
            fi
            
            # Truncate if too long
            if [ ''${#LABEL} -gt 40 ]; then
              LABEL="''${LABEL:0:37}..."
            fi
            
            sketchybar --set $NAME drawing=on label="$LABEL" icon="$ICON" icon.color="$COLOR"
            sketchybar --set sep_media drawing=on
            exit 0
          fi
        fi

        # Fallback: Try Spotify directly
        SPOTIFY_STATE=$(osascript -e 'tell application "System Events" to (name of processes) contains "Spotify"' 2>/dev/null)
        if [ "$SPOTIFY_STATE" = "true" ]; then
          PLAYING=$(osascript -e 'tell application "Spotify" to player state as string' 2>/dev/null)
          if [ "$PLAYING" = "playing" ]; then
            TRACK=$(osascript -e 'tell application "Spotify" to name of current track as string' 2>/dev/null)
            ARTIST=$(osascript -e 'tell application "Spotify" to artist of current track as string' 2>/dev/null)
            if [ -n "$TRACK" ]; then
              sketchybar --set $NAME drawing=on label="$ARTIST - $TRACK" icon="󰓇" icon.color="0xff1db954"
              sketchybar --set sep_media drawing=on
              exit 0
            fi
          fi
        fi

        # Fallback: Check Music app
        MUSIC_STATE=$(osascript -e 'tell application "System Events" to (name of processes) contains "Music"' 2>/dev/null)
        if [ "$MUSIC_STATE" = "true" ]; then
          PLAYING=$(osascript -e 'tell application "Music" to player state as string' 2>/dev/null)
          if [ "$PLAYING" = "playing" ]; then
            TRACK=$(osascript -e 'tell application "Music" to name of current track as string' 2>/dev/null)
            ARTIST=$(osascript -e 'tell application "Music" to artist of current track as string' 2>/dev/null)
            if [ -n "$TRACK" ]; then
              sketchybar --set $NAME drawing=on label="$ARTIST - $TRACK" icon="󰎆" icon.color="0xfffc3c44"
              sketchybar --set sep_media drawing=on
              exit 0
            fi
          fi
        fi

        # Nothing playing
        sketchybar --set $NAME drawing=off
        sketchybar --set sep_media drawing=off
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
