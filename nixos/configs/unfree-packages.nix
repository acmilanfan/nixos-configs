{ lib, ...}: {

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "corefonts"
    "hplip"
    "Oracle_VM_VirtualBox_Extension_Pack"
    "teamviewer"
  ];

}
