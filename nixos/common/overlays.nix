final: prev: {
  warpd = final.callPackage ./pkgs/warpd.nix { };
  blueutil-tui = final.callPackage ./pkgs/blueutil-tui.nix { };
}
