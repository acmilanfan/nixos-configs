{ pkgs, ... }:
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
    ./nur.nix
    ./packages.nix
    ./shell.nix
    ./unstable-packages.nix
    ./rss.nix
    ./tmux.nix
    ./lazygit.nix
    ./ai-agents.nix
    ./ai-agents-options.nix
    ./opencode.nix
    ./opencode-telegram-bot.nix
    ./sops.nix
    ./vicinae.nix
  ]
  ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
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
