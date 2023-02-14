{ config, pkgs, ... }: {

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "ahci" "usb_storage" "usbhid" "sd_mod" ];

  boot.kernelModules = [ 
    "v4l2loopback" 
    "acpi_call" 
  ];

  boot.extraModulePackages = with config.boot.kernelPackages; [ acpi_call v4l2loopback ];

  boot.kernelPackages = pkgs.linuxPackages_latest;

}
