{ pkgs, ... }: {

  home.packages = with pkgs; [
    wine-staging
    winetricks
    #lutris
    #lutris-free
  ];

}
