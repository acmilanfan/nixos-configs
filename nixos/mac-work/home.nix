{
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ../common/home-darwin.nix
    ./git.nix
  ];

  home.username = "andreishumailov";
  home.homeDirectory = lib.mkForce "/Users/andreishumailov";
}