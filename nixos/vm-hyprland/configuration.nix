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

    # Remote deploys (`nixos-rebuild switch --target-host ...`) copy
    # locally-built (unsigned) store paths over SSH; the target daemon only
    # accepts those from a trusted user, otherwise it fails with "lacks a
    # signature by a trusted key".
    settings.trusted-users = [ "gentooway" ];
  };

  system.stateVersion = "26.05";

}
