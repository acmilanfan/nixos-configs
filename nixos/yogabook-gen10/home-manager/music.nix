{ pkgs, ... }: {

  # wine itself comes from packages.nix (wineWow64Packages.full); a second
  # wine here only lost the bin/ collisions to it.
  home.packages = with pkgs; [
    guitarix
    musescore
    ardour
    carla
    libjack2
    reaper
  ];
}
