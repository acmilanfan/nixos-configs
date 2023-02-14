{ pkgs, ... }: {

  home.packages = with pkgs; [
    libsForQt5.plasma-browser-integration
  ];

  nixpkgs.config.firefox.enablePlasmaBrowserIntegration = true;

  xdg.desktopEntries.open-in-vim = {
    type = "Application";
    exec = ''
      konsole -e \'vim %U\'
    '';
    name = "Open in VIM";
    noDisplay = true;
    mimeType = [ "text/*.nix" ];
  };

  xdg.mimeApps.associations.added = {
    "text/*.nix" = "open-in-vim.desktop";
  };

}
