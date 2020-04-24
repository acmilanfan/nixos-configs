{ ... }: {

  #services.safeeyes.enable = true;
  services.fprintd.enable = true;
  services.geoclue2.enable = true;
  services.autorandr.enable = true;
  services.greenclip.enable = true;

  programs.gnupg.agent.enable = true;

}
