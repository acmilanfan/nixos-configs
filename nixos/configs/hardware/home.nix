{ pkgs, ... }: {

  boot.supportedFilesystems = [ "ntfs" ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/cf3d8358-10b4-4315-9541-b9150c15326b";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/BC4E-B931";
      fsType = "vfat";
    };

  swapDevices =
    [ { device = "/dev/disk/by-uuid/bc44248a-641e-41e9-a118-a0da943f040a"; }
    ];
}
