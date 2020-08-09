{ pkgs, ... }: {

  environment.systemPackages = with pkgs; [
    wget 
    vim 
    acpi 
    tree 
    pciutils
    usbutils
    openconnect
  ];

  programs.light.enable = true;
}
