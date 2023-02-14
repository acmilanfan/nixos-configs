{ ... }: {

  imports = [
    ./bootloader.nix
    ./firmware.nix
    ./nix-settings.nix
    ./ssd.nix
  ];

}