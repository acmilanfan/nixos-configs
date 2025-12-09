{ pkgs, ... }: {

  imports = [
    ./../common
    ./configs
  ];

  nix = {
    package = pkgs.nixVersions.stable;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  system.stateVersion = "25.11";

}
