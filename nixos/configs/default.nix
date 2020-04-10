{ ... }: {

  imports =
    [ 
      ./bootloader.nix
      ./hosts.nix
      ./networking.nix
      ./system-packages.nix
      ./sound.nix
      ./services.nix
      ./fonts.nix
      ./environment.nix
      ./i18n.nix
      ./timezone.nix
      ./xserver.nix
      ./gnome.nix
      ./awesome.nix
      ./gc.nix
    ];

  system.stateVersion = "19.09";
}
