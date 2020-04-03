{ lib, ... }: {

  imports =[ 
    <nixpkgs/nixos/modules/installer/scan/not-detected.nix>
    ./opengl.nix
    ./tlp.nix
    ./boot.nix
    ./ssd.nix
  ]; 

  nix.maxJobs = lib.mkDefault 8;

  hardware.enableRedistributableFirmware = lib.mkDefault true;
}
