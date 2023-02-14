{ lib, config, ... }: {

  services.fprintd.enable = true;
  services.autorandr.enable = true;
  services.greenclip.enable = true;
  services.fwupd.enable = true;
  services.thermald.enable = lib.mkDefault true;
  programs.light.enable = true;
  programs.gnupg.agent.enable = true;

}
