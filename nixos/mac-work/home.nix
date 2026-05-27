{
  pkgs,
  lib,
  secrets,
  ...
}:

{
  imports = [
    ../common/home-darwin.nix
    ./git.nix
  ];

  home.username = "andreishumailov";
  home.homeDirectory = lib.mkForce "/Users/andreishumailov";

  # mac-work has an ANSI keyboard (mac-home has ISO)
  home.file.".config/kanata/kanata-homerow.kbd".source = lib.mkForce ../../dotfiles/kanata/kanata.kbd;
  home.file.".config/kanata/kanata-sweep.kbd".source = lib.mkForce ../../dotfiles/kanata/kanata-sweep.kbd;
  home.file.".config/kanata/kanata-default.kbd".source = lib.mkForce ../../dotfiles/kanata/kanata-default.kbd;
  home.file.".config/kanata/kanata-angle.kbd".source = lib.mkForce ../../dotfiles/kanata/kanata-angle.kbd;
  home.file.".config/kanata/kanata-disabled.kbd".source = lib.mkForce ../../dotfiles/kanata/kanata-disabled.kbd;
}