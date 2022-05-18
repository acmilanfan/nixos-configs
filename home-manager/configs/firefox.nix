{ config, pkgs, lib, ... }: {

  programs.firefox = {
#    extensions = lib.mkIf config.programs.firefox.enable (
#      with pkgs.nur.repos.rycee.firefox-addons;
#        [
#          browserpass
#          https-everywhere
#          link-cleaner
#          swedish-dictionary
#          ublock-origin
#          vimium
#        ] ++ builtins.attrValues (import ./firefox-extensions.nix {
#            inherit (pkgs) stdenv fetchurl;
#            buildFirefoxXpiAddon =
#            pkgs.nur.repos.rycee.firefox-addons.buildFirefoxXpiAddon;
#          })
#      );
#    package = pkgs.firefox-wayland;
    package = pkgs.firefox;
    profiles = {
      default = {
        isDefault = true;
        settings = {
          "browser.tabs.closeWindowWithLastTab" = true;
          "devtools.theme" = "dark";
          "experiments.activeExperiment" = false;
          "experiments.enabled" = false;
          "experiments.supported" = false;
          "dom.w3c_touch_events.enabled" = 1;
          "browser.download.useDownloadDir" = false;
          "browser.download.panel.showni" = true;
          "browser.fullscreen.autohide" = false;
          "browser.search.region" = "DE";
          "browser.startup.page" = 3;
        };
      };
    };
  };

  programs.browserpass = {
    enable = config.programs.firefox.enable;
    browsers = [ "firefox" ];
  };

  pam.sessionVariables = { MOZ_USE_XINPUT2 = "DEFAULT=1"; };

  nixpkgs.config.firefox.enableBrowserpass = true;
  nixpkgs.config.firefox.enableGnomeExtensions = true;

}
