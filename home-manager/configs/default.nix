{ ... }: {

  imports = [
      ./non-free-packages.nix
      ./packages.nix
      ./unstable-packages.nix

      ./firefox.nix
      ./redshift.nix
      ./password-store.nix
      ./rofi.nix
      ./awesome.nix
      ./kitty.nix
      ./alacritty.nix
      ./nur.nix
      ./gtk.nix
      ./xsession.nix
      ./screenlock.nix
      ./dconf.nix
      ./ssh.nix
      ./gpg.nix
      ./git-common.nix
      ./services.nix
      ./shell.nix
      ./neovim.nix
      ./ideavim.nix
      #./kde.nix
  ];

  programs.home-manager.enable = true;

  home.stateVersion = "22.11";
}
