{ config, pkgs, ... }: {

  boot.initrd.availableKernelModules =
    [ "xhci_pci" "nvme" "ahci" "usb_storage" "usbhid" "sd_mod" ];

  boot.kernelModules = [ "acpi_call" ];

  boot.extraModulePackages = with config.boot.kernelPackages; [ acpi_call ];

  boot.kernelPackages = pkgs.linuxPackages_latest;

}
