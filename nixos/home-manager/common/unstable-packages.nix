{ config, unstable, pkgs, ... }: {

  home.packages = [
    unstable.tdesktop
    unstable.jetbrains.idea-community
    # pkgs.jetbrains.idea-ultimate
    #genymotionPkgs.genymotion
    unstable.jdk
    unstable.davinci-resolve-studio
  ];

}
