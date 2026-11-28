{
  config,
  pkgs,
  lib,
  unstable,
  ...
}:
let
  hypr-iio-rotate-script = (pkgs.writeShellScriptBin "hypr-iio-rotate" (lib.readFile ./scripts/hypr-iio-rotate));
  # All lock starts go through hyprlock-session: it checks the compositor's
  # real lock state, reaps leaked hyprlock processes, and serializes starts.
  # TTY recovery for a wedged lock screen: `hyprlock-session restart`.
  hyprlock-session = pkgs.writeShellScriptBin "hyprlock-session" (
    lib.readFile ./scripts/hyprlock-session
  );
  hyprlock-proximity = pkgs.writeShellScriptBin "hyprlock-proximity" (
    lib.readFile ./scripts/hyprlock-proximity
  );
  hyprlock-absence = pkgs.writeShellScriptBin "hyprlock-absence" (
    lib.readFile ./scripts/hyprlock-absence
  );
  # hyprlock's "Scan Face" button; read by the hyprlock-proximity service.
  # Per-user runtime dir rather than a predictable /tmp path.
  hyprlock-face-trigger = pkgs.writeShellScript "hyprlock-face-trigger" ''
    touch "$XDG_RUNTIME_DIR/hyprlock_face_trigger"
  '';
in
{
  options.touchGestures =
    lib.mkEnableOption "touchscreen gesture binds via the yb-touchpad daemon (tablet hosts)";

  config = {
    home.sessionVariables = {
    XDG_CURRENT_DESKTOP = "Hyprland";
    XDG_SESSION_TYPE = "wayland";
    QT_QPA_PLATFORM = "wayland;xcb";
    # macOS-style stem darkening (also set system-wide in nixos/common/fonts.nix)
    FREETYPE_PROPERTIES = "cff:no-stem-darkening=0 autofitter:no-stem-darkening=0 type1:no-stem-darkening=0 t1cid:no-stem-darkening=0";
  };

  wayland.windowManager.hyprland = {
    enable = true;
    package = unstable.hyprland;
    # NixOS owns portal selection; the HM 26.05 module cannot override the
    # 1.5.0 portal package because it no longer takes a `hyprland` argument.
    portalPackage = null;
    xwayland.enable = true;

    # Whether to enable hyprland-session.target on hyprland startup
    systemd.enable = true;
    configType = "lua";
    plugins = with pkgs; [
      # No plugins needed — touch_gestures is built-in as of Hyprland 0.55+
    ];
    # HM generates the config header (incl. the dbus/systemd session
    # activation hook) and appends our config from dotfiles/
    extraConfig =
      lib.readFile ../../../dotfiles/hypr/hyprland.lua
      + lib.optionalString config.touchGestures
        (lib.readFile ../../../dotfiles/hypr/touch-gestures.lua);
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

          onclick = ${hyprlock-face-trigger}
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

  # Night tint only. Brightness is controlled by the DPCD hardware backlight
  # through brightnessctl; hyprsunset gamma stays at 100.
  services.hyprsunset = {
    enable = true;
  };

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        # Never trust `pidof hyprlock`: a leaked locker must not block new
        # locks. The wrapper reaps it and waits for the compositor lock.
        lock_cmd = "${hyprlock-session}/bin/hyprlock-session start";
        before_sleep_cmd = "${hyprlock-session}/bin/hyprlock-session start";
        after_sleep_cmd = "hyprctl dispatch \"hl.dsp.dpms({ action = 'on' })\"";
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
          on-timeout = "${hyprlock-session}/bin/hyprlock-session start";
        }
        {
          timeout = 330;
          on-timeout = "hyprctl dispatch \"hl.dsp.dpms({ action = 'off' })\"";
          on-resume = "hyprctl dispatch \"hl.dsp.dpms({ action = 'on' })\" && restore-sync-brightness";
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
    waybar
    swaynotificationcenter
    brightnessctl
    awww
    wl-clipboard
    grim
    slurp
    kanshi
    hypridle
    hyprlock
    hyprlock-session
    libnotify
    wlogout
    wdisplays
    wlr-randr
    nwg-drawer
    socat
    wvkbd
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
    (writeShellScriptBin "hypr-profile-tablet" (lib.readFile ./scripts/hypr-profile-tablet))
    (writeShellScriptBin "hypr-toggle-kb" (lib.readFile ./scripts/hypr-toggle-kb))
    (writeShellScriptBin "hypr-send-to-other-monitor" (
      lib.readFile ./scripts/hypr-send-to-other-monitor
    ))
    (writeShellScriptBin "hypr-focus-other-monitor" (lib.readFile ./scripts/hypr-focus-other-monitor))
    (writeShellScriptBin "hypr-cycle-layout" (lib.readFile ./scripts/hypr-cycle-layout))
    (writeShellScriptBin "hypr-powersave-mode" (lib.readFile ./scripts/hypr-powersave-mode))
    (writeShellScriptBin "hypr-animations-toggle" (lib.readFile ./scripts/hypr-animations-toggle))
    (writeShellScriptBin "hypr-layout-status" (lib.readFile ./scripts/hypr-layout-status))
    (writeShellScriptBin "hypr-layout-icon" (lib.readFile ./scripts/hypr-layout-icon))
    (writeShellScriptBin "hypr-kanata-menu" (lib.readFile ./scripts/hypr-kanata-menu))
    (writeShellScriptBin "hypr-power-watts" (lib.readFile ./scripts/hypr-power-watts))
    (writeShellScriptBin "hypr-focus-window" (lib.readFile ./scripts/hypr-focus-window))
    (writeShellScriptBin "hypr-timer" (lib.readFile ./scripts/hypr-timer))
    (writeShellScriptBin "hypr-commands" (lib.readFile ./scripts/hypr-commands))
    (writeShellScriptBin "hypr-ai-agents" (lib.readFile ./scripts/hypr-ai-agents))
    (writeShellScriptBin "hypr-tmux-client" (lib.readFile ./scripts/hypr-tmux-client))
    (writeShellScriptBin "hypr-expand-float" (lib.readFile ./scripts/hypr-expand-float))
    (writeShellScriptBin "hypr-focus-or-spawn" (lib.readFile ./scripts/hypr-focus-or-spawn))
    (writeShellScriptBin "hypr-reset-touch" (lib.readFile ./scripts/hypr-reset-touch))
    (writeShellScriptBin "hypr-iio-toggle" (lib.readFile ./scripts/hypr-iio-toggle))
    (writeShellScriptBin "hypr-touch-action" (lib.readFile ./scripts/hypr-touch-action))
    (writeShellScriptBin "hypr-waybar-toggle" (lib.readFile ./scripts/hypr-waybar-toggle))
    (writeShellScriptBin "hypr-bar-toggle" (lib.readFile ./scripts/hypr-bar-toggle))
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
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${hyprlock-proximity}/bin/hyprlock-proximity";
      Restart = "on-failure";
      RestartSec = 2;
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
  # these sensors (t480, vm) since the sensor files are missing.
  systemd.user.services.hyprlock-absence = {
    Unit = {
      Description = "Lock hyprlock when human presence sensors report absence";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${hyprlock-absence}/bin/hyprlock-absence";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  systemd.user.services.hypr-iio-rotate = {
    Unit = {
      Description = "Auto-rotation for Hyprland (Dual Monitor and Touch)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Environment = "PATH=${lib.makeBinPath [
        pkgs.bash
        config.wayland.windowManager.hyprland.finalPackage
        pkgs.iio-sensor-proxy
        pkgs.jq
        pkgs.coreutils
        pkgs.gawk
        pkgs.procps
        pkgs.libnotify
      ]}";
      ExecStart = "${hypr-iio-rotate-script}/bin/hypr-iio-rotate";
      Restart = "always";
      RestartSec = 2;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  };
}
