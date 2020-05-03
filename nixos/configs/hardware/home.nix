{ ... }: {

  boot.supportedFilesystems = [ "ntfs" ];

  fileSystems."/" = { 
    device = "/dev/disk/by-uuid/8daaa821-b568-4aa9-ac66-2952d9263f64";
    fsType = "ext4";
  };

  fileSystems."/home" = { 
    device = "/dev/disk/by-uuid/429ea259-1782-4d44-9806-b3d823a7def2";
    fsType = "ext4";
  };

  fileSystems."/boot" = { 
    device = "/dev/disk/by-uuid/FDD3-07E0";
    fsType = "vfat";
  };

  swapDevices = [ 
    { 
      device = "/dev/disk/by-uuid/7e45a1fd-3ec4-4f5d-871b-4eee120b456f"; 
    }
  ];

  boot.loader.grub.enable = true;
  boot.loader.grub.version = 2;
  boot.loader.grub.devices = [ "nodev" ];
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.useOSProber = true;

}
