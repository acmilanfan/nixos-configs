{ pkgs, ... }: {
  
  imports = [
    ./../common
    ./configs
    ./../configs/music.nix
  ];

  nix = {
    package = pkgs.nixFlakes;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  system.stateVersion = "23.11";

}
