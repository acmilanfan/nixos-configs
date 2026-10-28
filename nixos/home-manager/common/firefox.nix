{ config, pkgs, lib, ... }:

let
  # Width (px) of the vertical tab strip while it is expanded on hover.
  verticalTabsWidth = 455;
in {

  programs.firefox = {
    enable = true;
    # NUR, if this comes back: pkgs.nur doesn't exist here (HM gets pkgs via
    # extraSpecialArgs); use the pinned flake input, e.g.
    # (import inputs.nur { nurpkgs = pkgs; inherit pkgs; }).repos.rycee.firefox-addons
    #    extensions = lib.mkIf config.programs.firefox.enable (
    #      with pkgs.nur.repos.rycee.firefox-addons;
    #        [
    #          browserpass
    #          https-everywhere
    #          link-cleaner
    #          swedish-dictionary
    #          ublock-origin
    #          vimium
    #        ]
    #      );
    #package = pkgs.firefox-wayland;
    package = if pkgs.stdenv.isDarwin then null else pkgs.firefox;
    # package = pkgs.firefox-bin;

    # nixpkgs' firefox wrapper exports MOZ_LEGACY_PROFILES=1, so Firefox reads
    # profiles from ~/.mozilla/firefox. HM >= 26.05 defaults to the XDG path,
    # which Firefox then ignores — pin the legacy path and adopt the existing
    # profile directory so the managed settings/userChrome actually apply.
    # On 2026-09-01 we migrated back to the original 'default' profile
    # (cookies/history richer); 'g68skjlx.default' is kept as a backup.
    configPath = lib.mkIf pkgs.stdenv.isLinux ".mozilla/firefox";

    profiles = {
      default = {
        isDefault = true;
        path = lib.mkIf pkgs.stdenv.isLinux "default";
        userChrome = ''
          @namespace url("http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul"); /* set default namespace to XUL */
          * {
            font-family: Inter !important;
            font-weight: 500 !important;
          }
          #urlbar {
            font-size: 16pt !important
          }
          menupopup,popup {
            font-size: 13pt !important;
            # font-weight: bold !important;
          }
          .tabbrowser-tab .tab-label {
            font-size: 11pt !important; /* 13pt before vertical tabs; 12pt was too subtle */
            /* Trial (2026-10-25): no bold labels with vertical tabs.
               Restore with: font-weight: bold !important; */
            font-weight: 500 !important;
          }

          /* Vertical tabs: the same expanded width in every window. Firefox
             keeps a width per window (dragging the splitter sets it inline),
             so new and restored windows otherwise differ. */
          :root {
            --sidebar-expanded-launcher-width: ${toString verticalTabsWidth}px !important;
          }
          #sidebar-container[sidebar-launcher-expanded] {
            width: ${toString verticalTabsWidth}px !important;
          }

          /* Vertical tabs: hide the strip while the window has a single tab.
             The selected tab is always there, so any other visible tab means
             two or more. Moved offscreen instead of display:none, because
             Firefox measures the collapsed width to offset the page on hover. */
          #sidebar-container:not(:has(.tabbrowser-tab:not([selected], [hidden]))) {
            position: fixed !important;
            translate: 200vw !important;
            visibility: hidden !important;
          }
          #sidebar-container:not(:has(.tabbrowser-tab:not([selected], [hidden])))
            + #sidebar-launcher-splitter {
            display: none !important;
          }
        '';
        settings = {
          "browser.tabs.closeWindowWithLastTab" = true;
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          "layout.css.devPixelsPerPx" = -1.0;

          # --- Fonts (macOS-style rendering defaults) ---
          # Web content defaults resolve through fontconfig (sans-serif -> Inter).
          # UI weight comes from userChrome above; these pin the generic families.
          "font.name.sans-serif.x-western" = "Inter";
          "font.name.sans-serif.x-unicode" = "Inter";
          "font.name.sans-serif.x-cyrillic" = "Inter";
          "font.default.x-western" = "sans-serif";
          "font.default.x-unicode" = "sans-serif";
          "font.default.x-cyrillic" = "sans-serif";

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

          # Vertical tabs in the sidebar, on the right, expanding on hover.
          # (Trial started 2026-10-25; this used to disable the revamp.)
          "sidebar.revamp" = true;
          "sidebar.verticalTabs" = true;
          "sidebar.visibility" = "expand-on-hover";
          "sidebar.position_start" = false;
          # State for windows opened without a parent window (Dock, Hammerspoon,
          # `firefox --new-window`). Firefox saves the last closed window's
          # state here, and a hidden launcher then stays hidden in every such
          # window; this resets it on each start.
          "sidebar.backupState" = builtins.toJSON {
            panelOpen = false;
            launcherVisible = true;
            launcherExpanded = false;
            expandedLauncherWidth = verticalTabsWidth;
          };

          # Ctrl+Tab goes to the next tab in strip order; Hammerspoon's
          # firefox-tab-mode relies on it for j/k.
          "browser.ctrlTab.sortByRecentlyUsed" = false;

          # New Tab Page Clean-up
          "browser.newtabpage.activity-stream.feeds.topsites" = false;
          "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
          "browser.newtabpage.activity-stream.system.showWeatherOptIn" = false;
          "browser.newtabpage.activity-stream.section.highlights.includePocket" = false;

          # Disable Pocket
          "extensions.pocket.enabled" = false;

          # Reduce background network activity
          "network.prefetch-next" = false;
          "network.dns.disablePrefetch" = true;
          "beacon.enabled" = true;

          # Block all autoplay
          "media.autoplay.default" = 5;

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

}
