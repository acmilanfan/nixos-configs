{ ... }: {

  imports = [
    ./../home-manager/common
    ./home-manager
  ];

  programs.home-manager.enable = true;

  home.stateVersion = "24.11";

}
