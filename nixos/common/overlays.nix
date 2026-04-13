final: prev: {
  warpd = final.callPackage ./pkgs/warpd.nix { };
  blueutil-tui = final.callPackage ./pkgs/blueutil-tui.nix { };
  nvim-opener = final.callPackage ./pkgs/nvim-opener.nix {
    inherit (final) apple-sdk_14;
  };

  # ffmpeg-python's test suite calls the ffmpeg binary which gets SIGKILL'd
  # under the macOS nix sandbox (aarch64-darwin). Skip checks to unblock
  # the gftools → jetbrains-mono → fonts build chain.
  python3 = prev.python3.override {
    packageOverrides = pyFinal: pyPrev: {
      ffmpeg-python = pyPrev.ffmpeg-python.overrideAttrs (_: {
        doCheck = false;
        doInstallCheck = false;
      });
    };
  };
  python3Packages = final.python3.pkgs;
}
