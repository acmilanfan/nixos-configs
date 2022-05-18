{ pkgs, ... }: {

  environment.systemPackages = with pkgs; [
    wget 
    vim 
    acpi 
    tree 
    pciutils
    usbutils
    openconnect
    cudatoolkit
  ];

  programs.light.enable = true;
}
