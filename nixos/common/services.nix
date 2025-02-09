{ lib, ... }: {

  services.fprintd.enable = true;
  services.autorandr.enable = true;
  services.greenclip.enable = true;
  services.fwupd.enable = true;
  services.thermald.enable = lib.mkDefault true;
  programs.light.enable = true;
  programs.gnupg.agent.enable = true;

  services.syncthing = {
    enable = true;
    user = "gentooway";
    configDir = "/home/gentooway/.config/synchting";
    dataDir = "/home/gentooway/.config/synchting/db";
  };

  services.udev.extraRules = ''
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{serial}=="*vial:f64c2b3c*", MODE="0660", GROUP="users", TAG+="uaccess", TAG+="udev-acl"
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", MODE="0660", GROUP="users", TAG+="uaccess", TAG+="udev-acl"
  '';
}
