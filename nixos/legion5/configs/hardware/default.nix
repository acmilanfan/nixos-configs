{ ... }: {

  imports = [
    ./acpid.nix
    ./boot.nix
    ./file-systems.nix
    #./opengl.nix
    ./tlp.nix
    ./xserver-drivers-nvidia.nix
  ];

}
