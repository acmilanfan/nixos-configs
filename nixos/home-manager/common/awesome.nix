{ pkgs, ... }: {

  xdg.configFile = {
    "awesome/rc.lua".source = /home/gentooway/configs/nixos-configs/dotfiles/awesome/rc.lua;
    "awesome/awesome-wm-widgets".source = /home/gentooway/configs/nixos-configs/dotfiles/awesome/awesome-wm-widgets;
    "awesome/themes/purple/assets.lua".source = /home/gentooway/configs/nixos-configs/dotfiles/awesome/themes/purple/assets.lua;
    "awesome/themes/purple/theme.lua".source = /home/gentooway/configs/nixos-configs/dotfiles/awesome/themes/purple/theme.lua;
  };

}
