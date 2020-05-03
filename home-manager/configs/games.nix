{ pkgs, ... }: {

  home.packages = with pkgs; [
    wine-staging
    winetricks
    #appimage-run
    #wineWowPackages.staging
    #lutris
    #lutris-free
  ];

}
