{ pkgs, lib, ... }: {

  imports = [
    ./alacritty.nix
    # ./doom.nix
    ./firefox.nix
    ./git-common.nix
    ./gpg.nix
    ./ideavim.nix
    ./kitty.nix
    ./neovim.nix
    ./non-free-packages.nix
    ./nur.nix
    ./packages.nix
    ./rofi.nix
    ./shell.nix
    ./unstable-packages.nix
    ./rss.nix
    ./tmux.nix
    ./lazygit.nix
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    ./awesome.nix
    ./dconf.nix
    ./default-apps.nix
    ./gtk.nix
    ./password-store.nix
    ./qt.nix
    ./redshift.nix
    ./screenlock.nix
    ./services.nix
    ./xsession.nix
    ./greenclip.nix
  ];

  #backupFileExtension = "backup";
}
