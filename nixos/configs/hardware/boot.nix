{ config, pkgs, ... }: {

  boot.initrd.availableKernelModules = [ "nvme" ];
  boot.initrd.kernelModules = [ "dm-snapshot" "i915" ];

  boot.kernelModules = [ "kvm-intel" "acpi_call" ];
  boot.extraModulePackages = with config.boot.kernelPackages; [ acpi_call ];
  boot.kernelParams = [
    "nouveau.modeset=0"
    "i915.enable_fbc=1"
    "i915.enable_psr=2"
  ];

  boot.kernelPackages = pkgs.linuxPackages_4_19;

}
