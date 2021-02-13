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
      ./sway.nix
      ./gc.nix
      ./unfree-packages.nix
    ];

  system.stateVersion = "20.09";
}
