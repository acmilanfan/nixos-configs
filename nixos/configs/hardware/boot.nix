{ config, pkgs, ... }: 

let 
  unstable = import <unstable> { 
    config = {
      allowUnfree = true; 
    };

  };

in {
  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "ahci" "usb_storage" "usbhid" "sd_mod" ];

  boot.kernelModules = [ 
    "v4l2loopback" 
    "acpi_call" 
    "kvm-amd"
  ];
  boot.extraModulePackages = with config.boot.kernelPackages; [ acpi_call v4l2loopback ];
  boot.kernelParams = [
    #"nouveau.modeset=0"
    #"i915.enable_fbc=1"
    #"i915.enable_psr=0"
  ];

  #boot.kernelPackages = unstable.linuxPackages_latest;
  boot.kernelPackages = unstable.linuxPackages;

}
