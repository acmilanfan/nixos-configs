{ ... }: {

  services.xserver.videoDrivers = [ "nvidia" ];
  #hardware.nvidia.powerManagement.enable = true;
  #hardware.nvidia.prime.offload.enable = true;
  #services.xserver.videoDrivers = [ "modesetting" ];

}
