{
  pkgs,
  lib,
  config,
  secrets,
  ...
}:

{
  imports = [
    ../common/home-darwin.nix
    ./git.nix
  ];

  home.username = "gentooway";
  home.homeDirectory = lib.mkForce "/Users/gentooway";

  # Antigravity workspaces trusted at runtime on this machine only; merged
  # into antigravitySettings.trustedWorkspaces by ai-agents.nix.
  ai-agents.extraTrustedWorkspaces = [
    "${config.home.homeDirectory}/Projects/wd-backend-auth-hardening"
  ];

   home.file.".config/kanata/kanata-homerow.kbd".source = lib.mkForce ../../dotfiles/kanata/kanata-iso.kbd;
   home.file.".config/kanata/kanata-default.kbd".source = lib.mkForce ../../dotfiles/kanata/kanata-default-iso.kbd;
  home.file.".config/kanata/kanata-angle.kbd".source = lib.mkForce ../../dotfiles/kanata/kanata-angle-iso.kbd;
  home.file.".config/kanata/kanata-disabled.kbd".source = lib.mkForce ../../dotfiles/kanata/kanata-disabled.kbd;
  home.file.".config/kanata/kanata-training.kbd".source = lib.mkForce ../../dotfiles/kanata/kanata-training-iso.kbd;
}
