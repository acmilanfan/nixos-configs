{ ... }: {

  boot.initrd.luks.devices = {
    root = {
      name = "root";
      device = "/dev/disk/by-uuid/5ad4d625-ad34-4c23-af31-720bcde93216";
      preLVM = true;
      allowDiscards = true;
    };
  };

  fileSystems."/" = { 
    device = "/dev/disk/by-uuid/2c01476d-ce6a-4d85-b41c-ee8ad3a8178d";
    fsType = "ext4";
  };

  fileSystems."/home" = { 
    device = "/dev/disk/by-uuid/2b835681-7323-498d-8c22-3870c4626247";
    fsType = "ext4";
  };

  fileSystems."/boot" = { 
    device = "/dev/disk/by-uuid/489B-373A";
    fsType = "vfat";
  };

  swapDevices = [
    { 
      device = "/dev/disk/by-uuid/beda4edd-ab98-4aaf-a57d-acaf35e72d47"; 
    }
  ];

}
