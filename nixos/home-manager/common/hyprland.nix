{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  fuzzel-main = pkgs.fuzzel.overrideAttrs (old: {
    src = pkgs.fetchgit {
      url = "https://codeberg.org/dnkl/fuzzel.git";
      rev = "9fb7e6c9604d069b8b0c16871a8d8dc8d6e09973";
      sha256 = "sha256-rlP2+Okq8TUSfvk63HvjMrDyMDjjbpDxH3buhGi3b3Y=";
    };
  });
in
{

  home.sessionVariables = {
    XDG_CURRENT_DESKTOP = "Hyprland";
    XDG_SESSION_TYPE = "wayland";
    QT_QPA_PLATFORM = "wayland";
  };

  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;

    # Whether to enable hyprland-session.target on hyprland startup
    systemd.enable = true;
    plugins = with pkgs; [ hyprlandPlugins.hyprgrass ];
    extraConfig = lib.readFile ./../../../dotfiles/hypr/hyprland.conf;
  };

  # xdg.configFile = {
  #   "hypr/hyprland.conf".source = ./../../../dotfiles/hypr/hyprland.conf;
  # };

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
      }

      # uncomment to enable fingerprint authentication
      # auth {
      #     fingerprint {
      #         enabled = true
      #         ready_message = Scan fingerprint to unlock
      #         present_message = Scanning...
      #         retry_delay = 250 # in milliseconds
      #     }
      # }

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

          # Toggle keyboard visibility
          # onclick = kill -34 $(pidof wvkbd-mobintl)
          onclick = hypr-toggle-kb
      }
    '';
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
          on-resume = "dunstctl close";
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

  programs.vicinae = {
    enable = true;
    systemd = {
      enable = true;
      autoStart = true; # default: false
      # environment = {
      #   USE_LAYER_SHELL = 1;
      # };
    };
    settings = {
      close_on_focus_loss = true;
      consider_preedit = true;
      pop_to_root_on_close = true;
      favicon_service = "twenty";
      search_files_in_root = true;
      font = {
        normal = {
          size = 13;
          normal = "Roboto Medium";
        };
      };
      theme = {
        light = {
          name = "vicinae-light";
          icon_theme = "default";
        };
        dark = {
          # name = "vicinae-dark";
          name = "rose-pine";
          # name = "ayo-dark";
          icon_theme = "default";
        };
      };
      launcher_window = {
        opacity = 0.98;
      };
    };
    extensions = with inputs.vicinae-extensions.packages.${pkgs.stdenv.hostPlatform.system}; [
      bluetooth
      nix
      hypr-keybinds
      # Extension names can be found in the link below, it's just the folder names
    ];
  };

  programs.fuzzel = {
    enable = true;
    package = fuzzel-main;
    settings = {
      main = {
        font = "Roboto Mono:size=13";
        dpi-aware = "yes";

        # lines = 8;
        width = 36;

        horizontal-pad = 20;
        vertical-pad = 14;
        inner-pad = 10;

        layer = "overlay";
        minimal-lines = true;
      };

      border = {
        width = 2;
        radius = 10;
      };

      colors = {
        background = "192330ff";
        text = "cdcecff0";
        match = "82aaffff";

        selection = "26334dff";
        selection-text = "cdcecff0";
        selection-match = "82aaffff";

        border = "719cd6ff";
      };
    };
  };

  home.packages = with pkgs; [
    hyprland
    waybar
    dunst
    brightnessctl
    swww
    wl-clipboard
    cliphist
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
    zathura
    socat
    wvkbd
    iio-hyprland
    hyprpolkitagent
    iwmenu
    pwmenu
    bzmenu
    bemoji
    (writeShellScriptBin "hypr-profile" (lib.readFile ./scripts/hypr-profile))
    (writeShellScriptBin "hypr-profile-tablet" (lib.readFile ./scripts/hypr-profile-tablet))
    (writeShellScriptBin "hypr-toggle-kb" (lib.readFile ./scripts/hypr-toggle-kb))
    (writeShellScriptBin "hypr-send-to-other-monitor" (
      lib.readFile ./scripts/hypr-send-to-other-monitor
    ))
    (writeShellScriptBin "hypr-focus-other-monitor" (lib.readFile ./scripts/hypr-focus-other-monitor))
    (writeShellScriptBin "hypr-cycle-layout" (lib.readFile ./scripts/hypr-cycle-layout))
    (writeShellScriptBin "hypr-float-center" (lib.readFile ./scripts/hypr-float-center))
    (writeShellScriptBin "hypr-powersave-mode" (lib.readFile ./scripts/hypr-powersave-mode))
    (writeShellScriptBin "hypr-animations-toggle" (lib.readFile ./scripts/hypr-animations-toggle))
    (writeShellScriptBin "hypr-expand-float" (lib.readFile ./scripts/hypr-expand-float))
    (writeShellScriptBin "hypr-expand-float-recover" (lib.readFile ./scripts/hypr-expand-float-recover))
    (writeShellScriptBin "hypr-reset-touch" (lib.readFile ./scripts/hypr-reset-touch))
    (writeShellScriptBin "hypr-iio-toggle" (lib.readFile ./scripts/hypr-iio-toggle))
    (writeShellScriptBin "hypr-touch-action" (lib.readFile ./scripts/hypr-touch-action))
    (writeShellScriptBin "hypr-waybar-toggle" (lib.readFile ./scripts/hypr-waybar-toggle))
  ];

  systemd.user.services.iio-hyprland = {
    Unit = {
      Description = "Auto-rotation for Hyprland (Dual Monitor)";
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = pkgs.writeShellScript "iio-dual-runner" ''
        TRANSFORM_MAP="0,1,2,3"

        pkill iio-hyprland || true

        # Start for Top Screen
        ${pkgs.iio-hyprland}/bin/iio-hyprland eDP-1 --transform $TRANSFORM_MAP &
        # Start for Bottom Screen
        ${pkgs.iio-hyprland}/bin/iio-hyprland eDP-2 --transform $TRANSFORM_MAP &

        wait
      '';
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

}
