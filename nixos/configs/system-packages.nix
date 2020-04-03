{ pkgs, ... }: {

  environment.systemPackages = with pkgs; [
    wget 
    vim 
    acpi 
    tree 
    pciutils
    usbutils
  ];

  programs.light.enable = true;
}
