{ ... }: {

  #fileSystems."/" =
  #  { device = "/dev/disk/by-uuid/8daaa821-b568-4aa9-ac66-2952d9263f64";
  #    fsType = "ext4";
  #  };

  #fileSystems."/home" =
  #  { device = "/dev/disk/by-uuid/429ea259-1782-4d44-9806-b3d823a7def2";
  #    fsType = "ext4";
  #  };

  #fileSystems."/boot" =
  #  { device = "/dev/disk/by-uuid/47556e8b-d1e5-44c0-b955-91ef5e2e8715";
  #    fsType = "ext4";
  #  };

  #fileSystems."/boot" =
  #  { device = "/dev/disk/by-uuid/9DE9-CA9D";
  #    fsType = "vfat";
  #  };

  #swapDevices =
  #  [ { device = "/dev/disk/by-uuid/7e45a1fd-3ec4-4f5d-871b-4eee120b456f"; }
  #  ];

}
