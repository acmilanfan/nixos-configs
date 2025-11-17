{ config, unstable, pkgs, ... }: {

  home.packages = [
    unstable.telegram-desktop
    # unstable.jetbrains.idea-community
    # pkgs.jetbrains.idea-ultimate
    #genymotionPkgs.genymotion
    unstable.jdk
  ];

}
