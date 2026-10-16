{ config, pkgs, lib, ... }: {

  # Unfree is allowed globally (nixpkgsConfig in flake.nix); an HM-level
  # allowUnfreePredicate here was never applied (HM used the flake's pkgs).

  home.packages = with pkgs;
    lib.optionals (pkgs.stdenv.hostPlatform.system == "x86_64-linux") [
      slack
      # zoom-us
    ];
}
