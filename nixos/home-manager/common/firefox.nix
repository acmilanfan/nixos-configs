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

          # --- Battery Saving Optimizations ---
          # Reduce frequency of session saving (saves disk I/O and CPU)
          "browser.sessionstore.interval" = 60000; # 60 seconds instead of 15s

          # Enable strict tracking protection (blocks scripts that drain battery)
          "privacy.trackingprotection.enabled" = true;
          "privacy.trackingprotection.socialtracking.enabled" = true;

          # Force GPU acceleration
          "layers.acceleration.force-enabled" = true;
          "gfx.webrender.all" = true;

          # Disable cosmetic animations
          "toolkit.cosmeticAnimations.enabled" = false;

          # Tab unloading (automatically discard tabs when memory is low)
          "browser.tabs.unloadOnLowMemory" = true;

          # Reduce background tab activity
          "dom.timeout.background_throttling_max_budget" = 50;
          "dom.timeout.background_delay_ms" = 10000;

          # --- UI & Feature Clean-up ---
          # Disable AI Features & Chatbot
          "browser.ml.chat.enabled" = false;
          "browser.ml.chat.sidebar.enabled" = false;
          "browser.ml.chat.shortcuts" = false;
          "browser.ml.chat.page" = false;
          "browser.ml.linkPreview.enabled" = false;

          # Explicitly block all AI control points
          "browser.ai.control.default" = "blocked";
          "browser.ai.control.linkPreviewKeyPoints" = "blocked";
          "browser.ai.control.pdfjsAltText" = "blocked";
          "browser.ai.control.sidebarChatbot" = "blocked";
          "browser.ai.control.smartTabGroups" = "blocked";
          "browser.ai.control.translations" = "blocked";

          # Disable Sidebar Revamp / Vertical Tabs
          "sidebar.revamp" = false;
          "sidebar.verticalTabs" = false;
          "sidebar.visibility" = "hide-sidebar";

          # New Tab Page Clean-up
          "browser.newtabpage.activity-stream.feeds.topsites" = false;
          "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
          "browser.newtabpage.activity-stream.system.showWeatherOptIn" = false;
          "browser.newtabpage.activity-stream.section.highlights.includePocket" = false;

          # Disable Pocket
          "extensions.pocket.enabled" = false;

          # Disable Data Collection & Telemetry
          "datareporting.healthreport.uploadEnabled" = false;
          "datareporting.policy.dataSubmissionEnabled" = false;
          "toolkit.telemetry.enabled" = false;
          "toolkit.telemetry.unified" = false;
          "toolkit.telemetry.archive.enabled" = false;
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
