{ config, unstable, pkgs, ... }: {

  home.packages = [
    unstable.tdesktop
    unstable.jetbrains.idea-ultimate
    # pkgs.jetbrains.idea-ultimate
    #genymotionPkgs.genymotion
    unstable.jdk
  ];

}
