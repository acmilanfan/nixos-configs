{ ... }: {

  imports =
    [
      ./hosts.nix
      ./networking.nix
      ./system-packages.nix
      ./sound.nix
      ./services.nix
      ./fonts.nix
      ./environment.nix
      ./console.nix
      ./timezone.nix
      ./xserver.nix
      ./gnome.nix
      ./awesome.nix
      #./sway.nix
      ./gc.nix
      ./unfree-packages.nix
      #./printing.nix
    ];

  system.stateVersion = "21.11";
}
