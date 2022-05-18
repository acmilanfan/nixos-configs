{ lib, ...}: {

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "corefonts"
    "hplip"
    "Oracle_VM_VirtualBox_Extension_Pack"
    "teamviewer"
    "nvidia-x11"
    "nvidia-settings"
    "nvidia-persistenced"
    "cudatoolkit"
    "steam"
    "steam-original"
    "steam-runtime"
  ];

  programs.steam.enable = true;
}
