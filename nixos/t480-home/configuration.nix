{ pkgs, ... }: {

  imports = [
    ./../common
    ./configs
    ../configs/remote-access.nix
  ];

  nix = {
    package = pkgs.nixVersions.stable;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  system.stateVersion = "26.05";

}
