{ pkgs, ... }: {

  home.packages = with pkgs; [
    wine-staging
    winetricks
    appimage-run
    #lutris
    #lutris-free
  ];

}
