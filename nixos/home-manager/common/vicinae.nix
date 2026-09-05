{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  vicinaeSettings = {
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

  exts = inputs.vicinae-extensions.packages.${pkgs.stdenv.hostPlatform.system};

  # Extension names can be found in the link below, it's just the folder names
  # https://github.com/vicinaehq/extensions/tree/main/extensions
  linuxExtensions = [
    # bluetooth
    exts.nix
    exts.hypr-keybinds
  ];
  darwinExtensions = [ exts.nix ];
in
lib.mkMerge [
  # Linux: full HM module — nix-built server via systemd, wrapped binary
  # carries VICINAE_OVERRIDES so it picks up `settings`.
  (lib.mkIf pkgs.stdenv.isLinux {
    programs.vicinae = {
      enable = true;
      settings = vicinaeSettings;
      systemd = {
        enable = true;
        autoStart = true; # default: false
        # environment = {
        #   USE_LAYER_SHELL = 1;
        # };
      };
      extensions = linuxExtensions;
    };
  })

  # macOS: do NOT enable the HM module. Enabling it installs the nix-built
  # Vicinae.app (~/Applications/Home Manager Apps), which:
  #   - collides with the brew-cask Vicinae.app in LaunchServices/Raycast
  #   - runs its CLI through a bash wrapper, so TCC attributes permission
  #     prompts to "bash" instead of "Vicinae" (and store hashes change on
  #     every rebuild, silently dropping grants).
  # We run the cask app (darwin-startup) and only deploy config + extensions.
  (lib.mkIf pkgs.stdenv.isDarwin {
    # Settings: the module would normally deliver these via VICINAE_OVERRIDES
    # baked into the nix binary; the cask app reads the overrides file
    # instead (exported via `launchctl setenv` in darwin-startup).
    home.file.".config/vicinae/nix.json".source =
      (pkgs.formats.json { }).generate "vicinae-nix-settings" vicinaeSettings;

    # Same deployment layout the module uses on Linux (~/.local/share/vicinae,
    # which the macOS app reads too).
    xdg.dataFile = builtins.listToAttrs (
      map (item: {
        name = "vicinae/extensions/${item.name}";
        value.source = item;
      }) darwinExtensions
    );
  })
]
