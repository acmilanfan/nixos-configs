{ ... }: {

  boot.initrd.luks.devices = {
    root = {
      name = "root";
      device = "/dev/disk/by-uuid/751b5532-933e-410d-92ed-c6d3e6726ec8";
      preLVM = true;
      allowDiscards = true;
    };
  };

  fileSystems."/" = { 
    device = "/dev/disk/by-uuid/3076190a-cd62-442f-ada1-fbb1bed899d8";
    fsType = "ext4";
  };

  fileSystems."/home" = { 
    device = "/dev/disk/by-uuid/8e39877c-72af-41d0-a546-103f9f2e10a6";
    fsType = "ext4";
  };

  fileSystems."/boot" = { 
    device = "/dev/disk/by-uuid/BED8-662D";
    fsType = "vfat";
  };

  swapDevices = [
    { 
      device = "/dev/disk/by-uuid/15353a9b-6cc2-405d-a80b-5bb7e1052c3d"; 
    }
  ];

}
