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

      ./gtk.nix
      ./xsession.nix
      ./xscreensaver.nix
      ./dconf.nix
      ./ssh.nix
      ./gpg.nix
  ];

  programs.home-manager.enable = true;

  home.stateVersion = "19.09";
}