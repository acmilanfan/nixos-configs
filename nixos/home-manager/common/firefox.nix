{ config, pkgs, lib, ... }: {

  programs.firefox = {
    enable = true;
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
    #package = pkgs.firefox-wayland;

    package = if pkgs.stdenv.isDarwin then null else pkgs.firefox;
    # package = pkgs.firefox-bin;
    profiles = {
      default = {
        isDefault = true;
        userChrome = ''
          @namespace url("http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul"); /* set default namespace to XUL */
          * {
            font-family: Inter !important;
          }
          #urlbar {
            font-size: 16pt !important
          }
          menupopup,popup {
            font-size: 13pt !important;
            # font-weight: bold !important;
          }
          .tabbrowser-tab .tab-label {
            font-size: 13pt !important;
            font-weight: bold !important;
          }
        '';
        settings = {
          "browser.tabs.closeWindowWithLastTab" = true;
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          "layout.css.devPixelsPerPx" = -1.0;
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
