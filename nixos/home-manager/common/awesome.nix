{ pkgs, inputs, ... }:
let
  # The widgets rc.lua uses, taken from the pinned upstream checkout (the repo
  # holds many more), with the local logout-menu defaults patched in.
  awesomeWmWidgets = pkgs.runCommand "awesome-wm-widgets" { } ''
    mkdir $out
    for w in batteryarc calendar cpu fs logout-menu pactl ram volume; do
      cp -r ${inputs.awesome-wm-widgets}/$w-widget $out/
    done
    chmod -R u+w $out
    patch -d $out -p1 < ${./awesome-wm-widgets-logout-menu.patch}
  '';
in
{

  xdg.configFile = {
    "awesome/rc.lua".source = ./../../../dotfiles/awesome/rc.lua;
    "awesome/awesome-wm-widgets".source = awesomeWmWidgets;
    "awesome/themes/purple/assets.lua".source = ./../../../dotfiles/awesome/themes/purple/assets.lua;
    "awesome/themes/purple/theme.lua".source = ./../../../dotfiles/awesome/themes/purple/theme.lua;
  };

}
