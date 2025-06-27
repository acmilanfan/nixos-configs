{ pkgs, ... }: {

  imports = [
    ./../common
    ./configs
    ./../configs/music.nix
  ];

  nix = {
    package = pkgs.nixVersions.stable;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  system.stateVersion = "25.05";

}
