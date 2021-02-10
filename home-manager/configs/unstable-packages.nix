{ config, pkgs, ... }:

let 
  unstable = import <unstable> { 
    config = {
      allowUnfree = true; 
    }; 
  };
in {

  home.packages = [
    unstable.tdesktop
    unstable.jetbrains.idea-ultimate
    unstable.jdk
  ];

}
