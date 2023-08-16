{ config, pkgs, ... }: {

  boot.kernelModules = [
    "kvm-amd"
  ];

}
