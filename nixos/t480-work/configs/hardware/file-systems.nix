{ ... }: {

  boot.initrd.luks.devices = {
    root = {
      name = "root";
      device = "/dev/disk/by-uuid/36076a85-1aea-4d36-b9c8-607209ce05d0";
      preLVM = true;
      allowDiscards = true;
    };
  };

  fileSystems."/" = { 
    device = "/dev/disk/by-uuid/b53e5cd0-e812-430b-a007-9755f36ef797";
    fsType = "ext4";
  };

  fileSystems."/boot/efi" = { 
    device = "/dev/disk/by-uuid/F4FE-B7DA";
    fsType = "vfat";
  };

  swapDevices = [
    { 
      device = "/dev/disk/by-uuid/1cf3d766-b4ca-4cb8-9a0d-c3e930497a06"; 
    }
  ];

  boot.loader.efi.efiSysMountPoint = "/boot/efi";

}
