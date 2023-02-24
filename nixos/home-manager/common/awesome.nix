{ pkgs, ... }: {

  xdg.configFile = {
    "awesome/rc.lua".source = ./../../../dotfiles/awesome/rc.lua;
    "awesome/awesome-wm-widgets".source = ./../../../dotfiles/awesome/awesome-wm-widgets;
    "awesome/themes/purple/assets.lua".source = ./../../../dotfiles/awesome/themes/purple/assets.lua;
    "awesome/themes/purple/theme.lua".source = ./../../../dotfiles/awesome/themes/purple/theme.lua;
  };

}
