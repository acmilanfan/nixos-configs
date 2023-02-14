{ ... }: {

  services.xserver.displayManager.sessionCommands = ''
    xinput --set-prop '2.4G Mouse' 'libinput Natural Scrolling Enabled' 0
    xinput --set-prop '2.4G Mouse Mouse' 'libinput Natural Scrolling Enabled' 0  
  '';

  services.xserver.enable = true;
  services.xserver.dpi = 96;

  services.xserver.extraDisplaySettings = ''
    Option  "RegistryDwords"  "EnableBrightnessControl=1"
  '';

  services.logind.lidSwitch = "ignore";

}
