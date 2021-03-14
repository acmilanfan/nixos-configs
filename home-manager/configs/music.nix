{ pkgs, ... }: {

  home.packages = with pkgs; [
    wine-staging
    guitarix
    musescore
    ardour
    bitwig-studio3
    carla
    libjack2
  ];

}
