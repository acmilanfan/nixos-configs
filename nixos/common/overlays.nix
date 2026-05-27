final: prev: {
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
  warpd = if final.stdenv.hostPlatform.isDarwin
    then final.callPackage ./pkgs/warpd.nix { }
    else prev.warpd;
  blueutil-tui = if final.stdenv.hostPlatform.isDarwin
    then final.callPackage ./pkgs/blueutil-tui.nix { }
    else prev.blueutil-tui or null;

  syncmon = final.callPackage ./pkgs/syncmon.nix { };
}
