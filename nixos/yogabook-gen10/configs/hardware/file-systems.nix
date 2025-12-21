{ ... }: {

  # boot.initrd.luks.devices = {
  #   root = {
  #     name = "root";
  #     device = "/dev/disk/by-uuid/8ac3098d-07b7-4957-927d-6b01d0c77799";
  #     preLVM = true;
  #     allowDiscards = true;
  #   };
  # };

  boot.supportedFilesystems = [ "ntfs" "exfat" ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/ffc979a6-2c85-482f-8a6e-d81b712d13a6";
    fsType = "ext4";
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/55887ca6-f79b-4c6d-afc9-8839e3c0f704";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/72CB-4718";
    fsType = "vfat";
  };

  swapDevices = [
    {
      device = "/dev/disk/by-uuid/8ddbef5a-4f4e-4ec0-b09c-5c4664b1cfca";
    }
  ];

}
