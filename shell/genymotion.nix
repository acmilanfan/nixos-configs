{ pkgs ? import <nixpkgs> { 
  config = import ../home-manager/configs/genymotion.nix;
} }:

(pkgs.buildFHSUserEnv {
  name = "android-sdk-env";
  targetPkgs = pkgs: (with pkgs;
  [
    genymotion ntp 
  ]);
  runScript = "bash";
}).env
