{ ... }: {

  imports = [
    ./hardware
    ./awesome.nix
    ./console.nix
    ./environment.nix
    ./fonts.nix
    ./gc.nix
    ./gnome.nix
    ./hosts.nix
    ./networking.nix
    ./services.nix
    ./sound.nix
    ./ssh.nix
    ./system-packages.nix
    ./timezone.nix
    ./unfree-packages.nix
    ./xserver.nix
    ./xserver-display-manager.nix
    ./xserver-libinput.nix
    ./xserver-xkb.nix
  ];

}
