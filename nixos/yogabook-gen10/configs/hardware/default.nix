{ ... } : {

  imports = [
    ./acpid.nix
    ./file-systems.nix
    # ./../../../configs/xserver-drivers-intel.nix
  ];

  # /boot is the 260M Windows SYSTEM_DRV ESP, shared with Windows (~32M) and
  # the Lenovo backup (~11M). An x86_64 kernel + initrd is ~62M, so without a
  # limit every kernel bump keeps its files and the ESP fills up; the
  # bootloader then fails with ENOSPC copying the next initrd. Keep the two
  # newest boot entries; older generations remain in the system profile until
  # garbage collection.
  boot.loader.systemd-boot.configurationLimit = 2;

}
