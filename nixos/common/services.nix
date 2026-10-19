{ config, lib, username, ... }: {

  # services.fprintd.enable = true;
  services.autorandr.enable = true;
  services.greenclip.enable = !config.programs.hyprland.enable;
  services.fwupd.enable = true;
  services.thermald.enable = lib.mkDefault true;
  hardware.acpilight.enable = true;
  programs.gnupg.agent.enable = true;

  services.syncthing = {
    enable = true;
    user = username;
    # configDir defaults to <dataDir>/.config/syncthing (database included).
    dataDir = config.users.users.${username}.home;
  };

  # The config/database used to live in a misspelt ~/.config/synchting. Move
  # it once so the device ID, keys and index survive. syncthing is stopped
  # before activation (its unit changed), so nothing has the files open.
  system.activationScripts.syncthingConfigDir = ''
    old=${config.services.syncthing.dataDir}/.config/synchting
    new=${config.services.syncthing.configDir}
    if [ -d "$old" ] && [ ! -e "$new/config.xml" ]; then
      [ -e "$new" ] && mv "$new" "$new.before-move.$(date +%s)"
      mv "$old" "$new"
    fi
  '';

  services.udev.extraRules = ''
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{serial}=="*vial:f64c2b3c*", MODE="0660", GROUP="users", TAG+="uaccess", TAG+="udev-acl"
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", MODE="0660", GROUP="users", TAG+="uaccess", TAG+="udev-acl"
  '';
}
