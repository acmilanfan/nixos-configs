{ pkgs, ... }: {

  home.packages = with pkgs; [
    wine-staging
    guitarix
    musescore
    ardour
    carla
    libjack2
  ];

}
