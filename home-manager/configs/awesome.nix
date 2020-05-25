{ pkgs, ... }: {

  xdg.configFile = {
    "awesome/rc.lua".source = ../../dotfiles/awesome/rc.lua;
    "awesome/power_widget.lua".source = ../../dotfiles/awesome/power_widget.lua;
    "awesome/themes/purple/assets.lua".source = ../../dotfiles/awesome/themes/purple/assets.lua;
    "awesome/themes/purple/theme.lua".source = ../../dotfiles/awesome/themes/purple/theme.lua;
  };

}
