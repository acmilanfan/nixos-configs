{ config, pkgs, ... }: {

  imports = [
      ./autorandr-home.nix
      ./git-home.nix
      ./music.nix
      ./games.nix
      ./stream.nix
  ];

}
