{ ... }: {

  #services.safeeyes.enable = true;
  services.fprintd.enable = true;
  services.geoclue2.enable = true;
  services.autorandr.enable = true;
  services.greenclip.enable = true;

  #virtualisation.virtualbox.host.enable = true;
  #virtualisation.virtualbox.host.enableExtensionPack = true;
  #users.extraGroups.vboxusers.members = [ "andrei" ];

  #virtualisation.anbox.enable = true;
  #programs.adb.enable = true;
  #users.users.andrei.extraGroups = [ "adbusers" ];

  #services.teamviewer.enable = true;

  programs.gnupg.agent.enable = true;

}
