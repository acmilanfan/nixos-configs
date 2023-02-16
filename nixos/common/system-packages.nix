{ pkgs, ... }: {

  environment.systemPackages = with pkgs; [
    wget 
    acpi
    tree 
    pciutils
    usbutils
    openconnect
    curlFull
    killall
    xclip
  ];

}
