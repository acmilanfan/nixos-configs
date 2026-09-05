{
  pkgs,
  lib,
  ...
}:
let
  hypr-iio-rotate-script = (pkgs.writeShellScriptBin "hypr-iio-rotate" (lib.readFile ./scripts/hypr-iio-rotate));
in
{
  home.sessionVariables = {
    XDG_CURRENT_DESKTOP = "Hyprland";
    XDG_SESSION_TYPE = "wayland";
    QT_QPA_PLATFORM = "wayland";
    # macOS-style stem darkening (also set system-wide in nixos/common/fonts.nix)
    FREETYPE_PROPERTIES = "cff:no-stem-darkening=0 autofitter:no-stem-darkening=0 type1:no-stem-darkening=0 t1cid:no-stem-darkening=0";
  };

  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;

    # Whether to enable hyprland-session.target on hyprland startup
    systemd.enable = true;
    configType = "lua";
    plugins = with pkgs; [
      # No plugins needed — touch_gestures is built-in as of Hyprland 0.55+
    ];
    # HM generates the config header (incl. the dbus/systemd session
    # activation hook) and appends our config from dotfiles/
    extraConfig = lib.readFile ../../../dotfiles/hypr/hyprland.lua;
  };

  xdg.configFile."hypr/hyprsunset.conf".source = ../../../dotfiles/hypr/hyprsunset.conf;

  home.file = {
    ".config/waybar/config".source = ../../../dotfiles/waybar/config;
    ".config/waybar/config-hypr-top".source = ../../../dotfiles/waybar/config-hypr-top;
    ".config/waybar/config-hypr-bottom".source = ../../../dotfiles/waybar/config-hypr-bottom;
    ".config/waybar/config-hypr-external".source = ../../../dotfiles/waybar/config-hypr-external;
    ".config/waybar/style.css".source = ../../../dotfiles/waybar/style.css;
    ".config/waybar/style-hypr.css".source = ../../../dotfiles/waybar/style-hypr.css;
  };

  programs.hyprlock = {
    enable = true;
    # TODO: source from a dotfiles file
    extraConfig = ''
      # sample hyprlock.conf
      # for more configuration options, refer https://wiki.hyprland.org/Hypr-Ecosystem/hyprlock
      #
      # rendered text in all widgets supports pango markup (e.g. <b> or <i> tags)
      # ref. https://wiki.hyprland.org/Hypr-Ecosystem/hyprlock/#general-remarks
      #
      # shortcuts to clear password buffer: ESC, Ctrl+U, Ctrl+Backspace
      #
      # you can get started by copying this config to ~/.config/hypr/hyprlock.conf
      #

      $font = Monospace

      general {
          hide_cursor = false
          immediate_render = true
      }

      animations {
          enabled = true
          bezier = linear, 1, 1, 0, 0
          animation = fadeIn, 1, 5, linear
          animation = fadeOut, 1, 5, linear
          animation = inputFieldDots, 1, 2, linear
      }

      background {
          monitor =
          path = screenshot
          blur_passes = 3
      }

      input-field {
          monitor =
          size = 20%, 5%
          outline_thickness = 3
          inner_color = rgba(0, 0, 0, 0.0) # no fill

          outer_color = rgba(33ccffee) rgba(00ff99ee) 45deg
          check_color = rgba(00ff99ee) rgba(ff6633ee) 120deg
          fail_color = rgba(ff6633ee) rgba(ff0066ee) 40deg

          font_color = rgb(143, 143, 143)
          fade_on_empty = false
          rounding = 15

          font_family = $font
          placeholder_text = Input password...
          fail_text = $PAMFAIL

          # uncomment to use a letter instead of a dot to indicate the typed password
          # dots_text_format = *
          # dots_size = 0.4
          dots_spacing = 0.3

          # uncomment to use an input indicator that does not show the password length (similar to swaylock's input indicator)
          # hide_input = true

          position = 0, -20
          halign = center
          valign = center
      }

      # TIME
      label {
          monitor =
          text = $TIME # ref. https://wiki.hyprland.org/Hypr-Ecosystem/hyprlock/#variable-substitution
          font_size = 90
          font_family = $font

          position = -30, 0
          halign = right
          valign = top
      }

      # DATE
      label {
          monitor =
          text = cmd[update:60000] date +"%A, %d %B %Y" # update every 60 seconds
          font_size = 25
          font_family = $font

          position = -30, -150
          halign = right
          valign = top
      }

      label {
          monitor =
          text = $LAYOUT[en,ru,de]
          font_size = 24
          onclick = hyprctl switchxkblayout all next

          position = 250, -20
          halign = center
          valign = center
      }

      # FACE ID BUTTON
      shape {
          monitor =
          size = 200, 50
          color = rgba(200, 200, 200, 0.1)
          rounding = 10
          border_size = 2
          border_color = rgba(200, 200, 200, 0.5)

          position = 0, -120
          halign = center
          valign = center

          onclick = touch /tmp/hyprlock_face_trigger
      }

      label {
          monitor =
          text = 👤 Scan Face
          color = rgba(200, 200, 200, 1.0)
          font_size = 16
          font_family = $font

          position = 0, -120
          halign = center
          valign = center
      }

      # KEYBOARD TOGGLE BUTTON
      label {
          monitor =
          text = ⌨️
          color = rgba(200, 200, 200, 1.0)
          font_size = 28
          font_family = $font

          # Positioned to the left of the input field (symmetric to layout label)
          position = -250, -20
          halign = center
          valign = center

          onclick = hypr-toggle-kb
      }
    '';
  };

  services.swaync = {
    enable = true;
  };

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "hyprlock";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };

      listener = [
        {
          timeout = 270;
          on-timeout = ''notify-send -u critical -t 30000 "Locking screen in 30 seconds"'';
          on-resume = "swaync-client -C --close-latest";
        }
        {
          timeout = 300;
          on-timeout = "set-sync-brightness 2";
          on-resume = "restore-sync-brightness";
        }
        {
          timeout = 300;
          on-timeout = "hyprlock";
        }
        {
          timeout = 330;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on && restore-sync-brightness";
        }
        {
          timeout = 1800;
          on-timeout = "systemctl suspend";
        }
      ];
    };
  };

  services.cliphist = {
    enable = true;
  };

  systemd.user.services.cliphist = {
    Unit = {
      After = lib.mkForce [ "graphical-session.target" ];
      PartOf = lib.mkForce [ "graphical-session.target" ];
    };
    Install = {
      WantedBy = lib.mkForce [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = lib.mkForce "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist -max-dedupe-search 10 -max-items 500 store";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  programs.satty = {
    enable = true;
    settings = {
      # general = {
      #   fullscreen = true;
      #   corner-roundness = 12;
      #   initial-tool = "brush";
      #   output-filename = "/tmp/test-%Y-%m-%d_%H:%M:%S.png";
      # };
      # color-palette = {
      #   palette = [
      #     "#00ffff"
      #     "#a52a2a"
      #     "#dc143c"
      #     "#ff1493"
      #     "#ffd700"
      #     "#008000"
      #   ];
      # };
    };
  };

  home.packages = with pkgs; [
    hyprland
    waybar
    swaynotificationcenter
    brightnessctl
    hyprsunset
    awww
    wl-clipboard
    grim
    slurp
    kanshi
    hypridle
    hyprlock
    libnotify
    wlogout
    wdisplays
    wlr-randr
    nwg-drawer
    socat
    wvkbd
    iio-hyprland
    hyprpolkitagent
    iwmenu
    pwmenu
    bzmenu
    bemoji
    ncdu
    impala
    bluetui
    wiremix
    yazi
    hypr-iio-rotate-script
    (writeShellScriptBin "hypr-touch-menu" (lib.readFile ./scripts/hypr-touch-menu))
    (writeShellScriptBin "hypr-reload-desktop" (lib.readFile ./scripts/hypr-reload-desktop))
    (writeShellScriptBin "hypr-previous-workspace" (lib.readFile ./scripts/hypr-previous-workspace))
    (writeShellScriptBin "hypr-profile" (lib.readFile ./scripts/hypr-profile))
    (writeShellScriptBin "hypr-toggle-kb" (lib.readFile ./scripts/hypr-toggle-kb))
    (writeShellScriptBin "hypr-send-to-other-monitor" (
      lib.readFile ./scripts/hypr-send-to-other-monitor
    ))
    (writeShellScriptBin "hypr-focus-other-monitor" (lib.readFile ./scripts/hypr-focus-other-monitor))
    (writeShellScriptBin "hypr-cycle-layout" (lib.readFile ./scripts/hypr-cycle-layout))
    (writeShellScriptBin "hypr-powersave-mode" (lib.readFile ./scripts/hypr-powersave-mode))
    (writeShellScriptBin "hypr-animations-toggle" (lib.readFile ./scripts/hypr-animations-toggle))
    (writeShellScriptBin "hypr-layout-status" (lib.readFile ./scripts/hypr-layout-status))
    (writeShellScriptBin "hypr-power-watts" (lib.readFile ./scripts/hypr-power-watts))
    (writeShellScriptBin "hypr-focus-window" (lib.readFile ./scripts/hypr-focus-window))
    (writeShellScriptBin "hypr-timer" (lib.readFile ./scripts/hypr-timer))
    (writeShellScriptBin "hypr-commands" (lib.readFile ./scripts/hypr-commands))
    (writeShellScriptBin "hypr-ai-agents" (lib.readFile ./scripts/hypr-ai-agents))
    (writeShellScriptBin "hypr-expand-float" (lib.readFile ./scripts/hypr-expand-float))
    (writeShellScriptBin "hypr-iio-rotate" (lib.readFile ./scripts/hypr-iio-rotate))
    (writeShellScriptBin "hypr-focus-or-spawn" (lib.readFile ./scripts/hypr-focus-or-spawn))
    (writeShellScriptBin "hypr-reset-touch" (lib.readFile ./scripts/hypr-reset-touch))
    (writeShellScriptBin "hypr-iio-toggle" (lib.readFile ./scripts/hypr-iio-toggle))
    (writeShellScriptBin "hypr-touch-action" (lib.readFile ./scripts/hypr-touch-action))
    (writeShellScriptBin "hypr-waybar-toggle" (lib.readFile ./scripts/hypr-waybar-toggle))
    (writeShellScriptBin "hypr-idle-inhibit" (lib.readFile ./scripts/hypr-idle-inhibit))
    wlinhibit
    wtype
  ];

  systemd.user.services.warpd = {
    Unit = {
      Description = "A modal keyboard-driven pointer manipulation tool";
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.warpd}/bin/warpd -f";
      Restart = "always";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  systemd.user.services.hyprlock-proximity = {
    Unit = {
      Description = "Trigger hyprlock on proximity sensor";
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = pkgs.writeShellScript "prox-trigger" ''
        SENSOR1="/sys/bus/iio/devices/iio:device1/in_proximity0_raw"
        SENSOR2="/sys/bus/iio/devices/iio:device2/in_proximity0_raw"
        TRIGGER_FILE="/tmp/hyprlock_face_trigger"
        LAST_STATE=0
        WAS_LOCKED=0
        LAST_TRIGGER_TIME=0

        while true; do
          if pgrep -x "hyprlock" > /dev/null; then
            CURRENT_TIME=$(date +%s)

            # Combine both sensors (if either is 1, presence is detected)
            STATE1=0
            STATE2=0
            [ -f "$SENSOR1" ] && STATE1=$(cat "$SENSOR1")
            [ -f "$SENSOR2" ] && STATE2=$(cat "$SENSOR2")
            STATE=$((STATE1 | STATE2))

            TRIGGER=0
            if [ "$STATE" -eq 1 ]; then
              # 1. Trigger on approach (0 -> 1)
              if [ "$LAST_STATE" -eq 0 ]; then
                echo "Proximity detected (approach)! Waking up hyprlock..."
                TRIGGER=1
              # 2. Trigger on initial lock if already present
              elif [ "$WAS_LOCKED" -eq 0 ]; then
                echo "Proximity detected (initial lock)! Waking up hyprlock..."
                TRIGGER=1
              # 3. Periodic re-trigger while present (every 10 seconds)
              elif [ $((CURRENT_TIME - LAST_TRIGGER_TIME)) -ge 10 ]; then
                echo "Proximity detected (continuous presence)! Re-waking hyprlock..."
                TRIGGER=1
              fi
            fi

            if [ "$TRIGGER" -eq 1 ]; then
              sleep 0.2
              ${pkgs.wtype}/bin/wtype -P Return -p Return
              LAST_TRIGGER_TIME=$CURRENT_TIME
            fi

            if [ -f "$TRIGGER_FILE" ]; then
              echo "Manual trigger detected! Waking up hyprlock..."
              rm -f "$TRIGGER_FILE"
              sleep 0.1
              ${pkgs.wtype}/bin/wtype -P Return -p Return
              LAST_TRIGGER_TIME=$CURRENT_TIME
            fi

            LAST_STATE=$STATE
            WAS_LOCKED=1
          else
            WAS_LOCKED=0
            LAST_STATE=0
            LAST_TRIGGER_TIME=0
          fi
          sleep 0.5
        done
      '';
      Restart = "always";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # Manual idle inhibitor, started/stopped on demand via the hypr-idle-inhibit
  # CLI (waybar button now, Quickshell later). Unit active = idle inhibited:
  # honored by hypridle via the wayland idle-inhibit protocol, and checked by
  # hyprlock-absence so presence-based locking also respects the toggle.
  systemd.user.services.hypr-idle-inhibit = {
    Unit = {
      Description = "Manual wayland idle inhibitor (wlinhibit)";
    };
    Service = {
      ExecStart = "${pkgs.wlinhibit}/bin/wlinhibit";
      Restart = "always";
      RestartSec = 2;
    };
  };

  # Lock-on-absence counterpart to hyprlock-proximity (which wakes on approach):
  # when the HPS sensors report no human presence continuously for
  # ABSENCE_LOCK_DELAY seconds, lock the screen. No-ops on machines without
  # these sensors (z16, t480, vm) since the sensor files are missing.
  systemd.user.services.hyprlock-absence = {
    Unit = {
      Description = "Lock hyprlock when human presence sensors report absence";
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = pkgs.writeShellScript "absence-trigger" ''
        SENSOR1="/sys/bus/iio/devices/iio:device1/in_proximity0_raw"
        SENSOR2="/sys/bus/iio/devices/iio:device2/in_proximity0_raw"
        ABSENCE_LOCK_DELAY=5
        POLL_INTERVAL=0.5

        if [ ! -f "$SENSOR1" ] && [ ! -f "$SENSOR2" ]; then
          echo "No proximity sensors found; exiting."
          exit 0
        fi

        ABSENT_SINCE=0

        while true; do
          if pgrep -x "hyprlock" > /dev/null; then
            # Already locked; wake-on-approach service handles this side.
            ABSENT_SINCE=0
          elif systemctl --user is-active --quiet hypr-idle-inhibit.service; then
            # Manual idle inhibitor active: user asked not to be locked.
            ABSENT_SINCE=0
          else
            STATE1=0
            STATE2=0
            [ -f "$SENSOR1" ] && STATE1=$(cat "$SENSOR1")
            [ -f "$SENSOR2" ] && STATE2=$(cat "$SENSOR2")
            # Non-zero = someone present (safer failure mode than ==1: sensor
            # garbage keeps the screen unlocked and idle-lock stays the fallback)
            STATE=$((STATE1 | STATE2))

            NOW=$(date +%s)
            if [ "$STATE" -eq 0 ]; then
              if [ "$ABSENT_SINCE" -eq 0 ]; then
                ABSENT_SINCE=$NOW
              elif [ $((NOW - ABSENT_SINCE)) -ge $ABSENCE_LOCK_DELAY ]; then
                echo "No presence for $ABSENCE_LOCK_DELAY s; locking..."
                ${pkgs.hyprlock}/bin/hyprlock
                ABSENT_SINCE=0
              fi
            else
              ABSENT_SINCE=0
            fi
          fi
          sleep $POLL_INTERVAL
        done
      '';
      Restart = "always";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  systemd.user.services.hypr-iio-rotate = {
    Unit = {
      Description = "Auto-rotation for Hyprland (Dual Monitor and Touch)";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Environment = "PATH=${lib.makeBinPath [
        pkgs.bash
        pkgs.hyprland
        pkgs.iio-sensor-proxy
        pkgs.jq
        pkgs.coreutils
        pkgs.gawk
        pkgs.procps
        pkgs.libnotify
      ]}";
      ExecStart = "${hypr-iio-rotate-script}/bin/hypr-iio-rotate";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

}
