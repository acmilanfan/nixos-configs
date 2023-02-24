{ ... } : {

  imports = [
    ./acpid.nix
    ./file-systems.nix
    ./../../../configs/xserver-drivers-intel.nix
#    <nixos-hardware/lenovo/thinkpad/t480>
  ];

}
