{ lib, ... }: {

  imports =[ 
    ./opengl.nix
    ./tlp.nix
    ./boot.nix
    ./ssd.nix
    ./games.nix
  ]; 

  nix.maxJobs = lib.mkDefault 8;

  hardware.enableRedistributableFirmware = lib.mkDefault true;
}
