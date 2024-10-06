{ config, pkgs, ... }: {

  boot.kernelModules = [ "kvm-amd" ];

  boot.extraModprobeConfig = ''
    options thinkpad_acpi  fan_control=1
  '';
}
