{ ... }: {

  boot.initrd.luks.devices = {
    root = {
      name = "root";
      device = "/dev/disk/by-uuid/8ac3098d-07b7-4957-927d-6b01d0c77799";
      preLVM = true;
      allowDiscards = true;
    };
  };

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/4a48705a-cba6-49f9-a1a7-71f60a0dc981";
    fsType = "ext4";
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/d28a0b5b-2272-415d-874d-34e86f8882d4";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/AEAD-1E7A";
    fsType = "vfat";
  };

  swapDevices = [
    {
      device = "/dev/disk/by-uuid/62f9943a-7b00-4ff8-8724-f5706176cc84";
    }
  ];

}
