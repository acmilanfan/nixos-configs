{ config, pkgs, ... }:

let 
  unstable = import <unstable> { 
    config = {
      allowUnfree = true; 
    }; 
  };

  #genymotionPkgs = import <nixpkgs> { config = import ./genymotion.nix; };

in {

  home.packages = [
    unstable.tdesktop
    unstable.jetbrains.idea-ultimate
    #genymotionPkgs.genymotion
    unstable.jdk
    unstable.notion-app-enhanced
  ];

}
