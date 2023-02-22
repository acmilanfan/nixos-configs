{ config, unstable, ... }: {

  home.packages = [
    unstable.tdesktop
    unstable.jetbrains.idea-ultimate
    #genymotionPkgs.genymotion
    unstable.jdk
  ];

}
