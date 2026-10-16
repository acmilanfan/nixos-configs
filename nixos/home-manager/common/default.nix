# imports may not depend on `pkgs` (with useGlobalPkgs it comes from the
# config being built, so that recurses); HM's integration passes osClass
# ("nixos" or "darwin") as a special argument for exactly this.
{ lib, osClass, ... }:
{

  imports = [
    ./alacritty.nix
    ./ghostty.nix
    # ./doom.nix
    ./firefox.nix
    ./firefox-managed-storage.nix
    ./direnv.nix
    ./git-common.nix
    ./ideavim.nix
    ./kitty.nix
    ./neovim.nix
    ./non-free-packages.nix
    ./packages.nix
    ./shell.nix
    ./unstable-packages.nix
    ./rss.nix
    ./tmux.nix
    ./lazygit.nix
    ./ai-agents.nix
    ./ai-agents-options.nix
    ./agent-workflow.nix
    ./opencode.nix
    ./opencode-telegram-bot.nix
    ./sops.nix
    ./vicinae.nix
  ]
  ++ lib.optionals (osClass == "nixos") [
    ./awesome.nix
    ./dconf.nix
    ./default-apps.nix
    ./gtk.nix
    ./password-store.nix
    ./qt.nix
    ./redshift.nix
    ./gammastep.nix
    ./screenlock.nix
    ./services.nix
    ./xsession.nix
    ./greenclip.nix
    ./gpg.nix
    ./rofi.nix
    ./hyprland.nix
  ];

  #backupFileExtension = "backup";
}
