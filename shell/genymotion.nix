{ pkgs ? import <nixpkgs> { config.allowUnfree = true; } }:

# nixpkgs' genymotion (x86_64-linux only). The old 3.2.1 override in
# nixos/home-manager/configs/genymotion.nix no longer evaluates (it uses
# the removed `xdg_utils`) and is older than nixpkgs' own package.
(pkgs.buildFHSEnv {
  name = "android-sdk-env";
  targetPkgs = pkgs: (with pkgs;
  [
    genymotion ntp
  ]);
  runScript = "bash";
}).env
