{ pkgs, ... }: {

  home.packages = with pkgs; [
    wine-staging
    guitarix
    musescore
    audacity
    ardour
    reaper
  ];

}
