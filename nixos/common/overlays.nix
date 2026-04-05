final: prev: {
  warpd = final.callPackage ./pkgs/warpd.nix { };
  blueutil-tui = final.callPackage ./pkgs/blueutil-tui.nix { };
  nvim-opener = final.callPackage ./pkgs/nvim-opener.nix { 
    inherit (final) apple-sdk_14;
  };
}
