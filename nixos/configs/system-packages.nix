{ pkgs, ... }: {

  environment.systemPackages = with pkgs; [
    wget 
    vim 
    acpi 
    tree 
    pciutils
    usbutils
    #openconnect
    killall
  ];

  programs.light.enable = true;
}
