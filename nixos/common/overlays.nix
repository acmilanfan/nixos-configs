{ inputs }:
final: prev: {
  nvim-opener = final.callPackage ./pkgs/nvim-opener.nix {
    inherit (final) apple-sdk_14;
  };

  # ffmpeg-python's test suite calls the ffmpeg binary which gets SIGKILL'd
  # under the macOS nix sandbox (aarch64-darwin). Skip checks to unblock
  # the gftools → jetbrains-mono → fonts build chain. Darwin only: on Linux
  # the override would just turn every python3 dependant into a local build.
  python3 = if !final.stdenv.hostPlatform.isDarwin then prev.python3 else prev.python3.override {
    packageOverrides = pyFinal: pyPrev: {
      ffmpeg-python = pyPrev.ffmpeg-python.overrideAttrs (_: {
        doCheck = false;
        doInstallCheck = false;
      });
    };
  };
  python3Packages = if !final.stdenv.hostPlatform.isDarwin then prev.python3Packages else final.python3.pkgs;
  warpd = if final.stdenv.hostPlatform.isDarwin
    then final.callPackage ./pkgs/warpd.nix { }
    else prev.warpd;
  blueutil-tui = if final.stdenv.hostPlatform.isDarwin
    then final.callPackage ./pkgs/blueutil-tui.nix { src = inputs.blueutil-tui; }
    else prev.blueutil-tui or null;

  # arrow-azurefs-test tries to send Azure SDK telemetry over HTTPS
  # but the sandbox has no CA certs, causing "unable to get local issuer certificate"
  # (macOS sandbox; Linux uses the cached upstream build).
  arrow-cpp = if !final.stdenv.hostPlatform.isDarwin then prev.arrow-cpp else prev.arrow-cpp.overrideAttrs (old: {
    installCheckPhase = builtins.replaceStrings
      [ "--exclude-regex '^(" ]
      [ "--exclude-regex '^(arrow-azurefs-test|" ]
      old.installCheckPhase;
  });

  syncmon = final.callPackage ./pkgs/syncmon.nix { };

  tg2kobo = final.callPackage ./pkgs/tg2kobo.nix { };

  opencode-telegram-bot = final.callPackage ./pkgs/opencode-telegram-bot.nix { };

  opencode-agent-memory = final.callPackage ./pkgs/opencode-agent-memory { };

  opencode = final.callPackage ./pkgs/opencode.nix { inherit inputs; };

  mtplx = if final.stdenv.hostPlatform.isDarwin
    then final.callPackage ./pkgs/mtplx { inherit inputs; }
    else prev.mtplx or null;
}
