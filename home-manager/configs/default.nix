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
      ./nur.nix
      #./games.nix

      ./gtk.nix
      ./xsession.nix
      ./xscreensaver.nix
      ./dconf.nix
      ./ssh.nix
      ./gpg.nix
      ./git-common.nix
  ];

  programs.home-manager.enable = true;

  home.stateVersion = "20.03";
}
