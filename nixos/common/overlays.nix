{ inputs }:
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

  # arrow-azurefs-test tries to send Azure SDK telemetry over HTTPS
  # but the sandbox has no CA certs, causing "unable to get local issuer certificate"
  arrow-cpp = prev.arrow-cpp.overrideAttrs (old: {
    installCheckPhase = builtins.replaceStrings
      [ "--exclude-regex '^(" ]
      [ "--exclude-regex '^(arrow-azurefs-test|" ]
      old.installCheckPhase;
  });

  syncmon = final.callPackage ./pkgs/syncmon.nix { };

  mtplx = if final.stdenv.hostPlatform.isDarwin
    then final.callPackage ./pkgs/mtplx { inherit inputs; }
    else prev.mtplx or null;
}
