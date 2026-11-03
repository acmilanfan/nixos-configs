{ ... }: {

  imports = [
    ./../home-manager/common
    ./home-manager
    ../home-manager/configs/remote-access.nix
  ];

  programs.home-manager.enable = true;

  home.stateVersion = "26.05";

}
