{ ... }: {

  #services.safeeyes.enable = true;
  services.fprintd.enable = true; 
  
  #services.geoclue2.enable = true;

  #services.geoclue2.appConfig.redshift = {
  #  isAllowed = true;
  #  isSystem = false;
  #};

  #services.geoclue2.appConfig.firefox = {
  #  isAllowed = true;
  #  isSystem = false;
  #};

  services.autorandr.enable = true;
  services.greenclip.enable = true;

  #virtualisation.virtualbox.host.enable = true;
  #virtualisation.virtualbox.host.enableExtensionPack = true;
  #users.extraGroups.vboxusers.members = [ "gentooway" ];

  #virtualisation.anbox.enable = true;
  #programs.adb.enable = true;
  #users.users.gentooway.extraGroups = [ "adbusers" ];

  #services.teamviewer.enable = true;

  virtualisation.docker.enable = true;
  users.users.gentooway.extraGroups = [ "docker" ];

  programs.gnupg.agent.enable = true;

}
