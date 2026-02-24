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

  home.file.".config/kanata/kanata-homerow.kbd".source = lib.mkForce ../../dotfiles/kanata/kanata-iso.kbd;
  home.file.".config/kanata/kanata-default.kbd".source = lib.mkForce ../../dotfiles/kanata/kanata-default-iso.kbd;
  home.file.".config/kanata/kanata-angle.kbd".source = lib.mkForce ../../dotfiles/kanata/kanata-angle-iso.kbd;
}
