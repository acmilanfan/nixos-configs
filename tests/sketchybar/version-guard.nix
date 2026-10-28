let
  lock = builtins.fromJSON (builtins.readFile ../../flake.lock);
  input = lock.nodes.unstable-nixpkgs.locked;
  pkgs = (builtins.getFlake "github:${input.owner}/${input.repo}/${input.rev}").legacyPackages.aarch64-darwin;
in
(pkgs.callPackage ../../nixos/common/pkgs/sketchybar {
  sketchybar = pkgs.sketchybar.overrideAttrs (_: { version = "99.0.0"; });
}).drvPath
