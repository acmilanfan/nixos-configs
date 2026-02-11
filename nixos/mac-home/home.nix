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

  home.username = "gentooway";
  home.homeDirectory = lib.mkForce "/Users/gentooway";
}
