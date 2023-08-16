{ config, lib, ... }: {

  powerManagement.cpuFreqGovernor = 
    lib.mkIf config.services.tlp.enable (lib.mkForce null);

  services.tlp.enable = lib.mkDefault true;

}
