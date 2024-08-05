{ lib, ...}: {

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "corefonts"
    "cudatoolkit"
    "nvidia-x11"
    "nvidia-settings"
    "davinci-resolve"
  ];

}
