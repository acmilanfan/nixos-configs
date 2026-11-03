{ pkgs, ... }: {

  imports = [
    ./../common
    ./configs
    ../configs/remote-access.nix
    ./../configs/music.nix
  ];

  nix = {
    package = pkgs.nixVersions.stable;
    nixPath = [ ];
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  system.stateVersion = "26.05";

}
