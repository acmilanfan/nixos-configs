{ pkgs, lib, ... }:
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
    ".config/waybar/style.css".source = ../../../dotfiles/waybar/style.css;
    ".config/waybar/style-hypr.css".source = ../../../dotfiles/waybar/style-hypr.css;
  };

  programs.hyprlock = {
    enable = true;
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
        }
        {
          timeout = 300;
          on-timeout = "set-sync-brightness 2";
          # TODO: brightnessctl -r for both screens too
          on-resume = "brightnessctl -r";
        }
        {
          timeout = 300;
          on-timeout = "hyprlock";
        }
        {
          timeout = 330;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on && brightnessctl -r";
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
    wofi
    fuzzel
    anyrun
    (writeShellScriptBin "hypr-profile" (lib.readFile ./scripts/hypr-profile))
    (writeShellScriptBin "hypr-send-to-other-monitor" (
      lib.readFile ./scripts/hypr-send-to-other-monitor
    ))
    (writeShellScriptBin "hypr-focus-other-monitor" (lib.readFile ./scripts/hypr-focus-other-monitor))
    (writeShellScriptBin "hypr-cycle-layout" (lib.readFile ./scripts/hypr-cycle-layout))
    (writeShellScriptBin "hypr-float-center" (lib.readFile ./scripts/hypr-float-center))
    (writeShellScriptBin "hypr-powersave-mode" (lib.readFile ./scripts/hypr-powersave-mode))
    (writeShellScriptBin "hypr-animations-toggle" (lib.readFile ./scripts/hypr-animations-toggle))
  ];

}
