{ pkgs ? import <nixpkgs> { config.allowUnfree = true; } }:

# nixpkgs' genymotion (x86_64-linux only).
(pkgs.buildFHSEnv {
  name = "android-sdk-env";
  targetPkgs = pkgs: (with pkgs;
  [
    genymotion ntp
  ]);
  runScript = "bash";
}).env
