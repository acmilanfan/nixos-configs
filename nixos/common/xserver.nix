{ pkgs, ... }: {

  services.xserver.displayManager.sessionCommands = ''
    xinput --set-prop '2.4G Mouse' 'libinput Natural Scrolling Enabled' 0
    xinput --set-prop '2.4G Mouse Mouse' 'libinput Natural Scrolling Enabled' 0
    ${pkgs.xorg.xrdb}/bin/xrdb -merge <<EOF
      ! Nightfox colors for Xresources
      ! Style: nightfox
      ! Upstream: https://github.com/edeneast/nightfox.nvim/raw/main/extra/nightfox/nightfox.Xresources
      *background: #1a1b26
      *foreground: #cdcecf
      *color0:  #393b44
      *color1:  #c94f6d
      *color2:  #81b29a
      *color3:  #dbc074
      *color4:  #719cd6
      *color5:  #9d79d6
      *color6:  #63cdcf
      *color7:  #dfdfe0
      *color8:  #575860
      *color9:  #d16983
      *color10: #8ebaa4
      *color11: #e0c989
      *color12: #86abdc
      *color13: #baa1e2
      *color14: #7ad5d6
      *color15: #e4e4e5
    EOF
  '';

  services.xserver.enable = true;
  # services.xserver.dpi = 96;

  services.xserver.extraDisplaySettings = ''
    Option  "RegistryDwords"  "EnableBrightnessControl=1"
  '';

  services.logind.lidSwitch = "ignore";

}
