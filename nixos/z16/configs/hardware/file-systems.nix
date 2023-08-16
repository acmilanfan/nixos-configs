{ pkgs, ... }: {

  boot.supportedFilesystems = [ "ntfs" ];

  boot.initrd.luks.devices = {
    root = {
      name = "root";
      device = "/dev/disk/by-uuid/09ba577c-532f-42ee-9b95-41a02fe9d907";
      preLVM = true;
      allowDiscards = true;
    };
  };

  fileSystems."/" = { 
    device = "/dev/disk/by-uuid/4b7da850-83b9-4460-8200-a24c62bca509";
    fsType = "ext4";
  };

  fileSystems."/home" = { 
    device = "/dev/disk/by-uuid/2568459d-1e92-491d-9cac-26ee21a2a5ca";
    fsType = "ext4";
  };

  fileSystems."/boot" = { 
    device = "/dev/disk/by-uuid/C708-DBFE";
    fsType = "vfat";
  };

  swapDevices = [
    { 
      device = "/dev/disk/by-uuid/2e0a46e4-5fb3-4ed4-872d-a8744c3c020c"; 
    }
  ];
}
