{ config, pkgs, lib, ... }: {

  programs.firefox = {
    extensions = lib.mkIf config.programs.firefox.enable (
      with pkgs.nur.repos.rycee.firefox-addons; [
        #anchors-reveal
        browserpass
        #cookie-autodelete
        #dark-night-mode
        #decentraleyes
        #greasemonkey
        https-everywhere
        link-cleaner
        #privacy-badger
        #reddit-enhancement-suite
        #save-page-we
        #stylus
        #swedish-dictionary
        ublock-origin
      ]
    );
    #profiles = {
    #  default = {
    #    isDefault = true;
    #    settings = {
    #      "browser.tabs.closeWindowWithLastTab" = false;
    #      "devtools.theme" = "dark";
    #      "experiments.activeExperiment" = false;
    #      "experiments.enabled" = false;
    #      "experiments.supported" = false;
    #      "general.smoothScroll" = false;
    #      "dom.w3c_touch_events.enabled" = "1";
    #    };
    #  };
    #};
  };
  
  #programs.browserpass = {     
  #  enable = config.programs.firefox.enable;     
  #  browsers = [ "firefox" ];   
  #};

  #pam.sessionVariables = {
  #  MOZ_USE_XINPUT2="DEFAULT=1";
  #};

  nixpkgs.config.firefox.enableBrowserpass = true;
  nixpkgs.config.firefox.enableGnomeExtensions = true;

}
