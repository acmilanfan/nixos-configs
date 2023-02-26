{ pkgs, ... }: {
  
  imports = [
    ./../common
    ./configs
  ];

  nix = {
    package = pkgs.nixFlakes;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  system.stateVersion = "22.11";

}
