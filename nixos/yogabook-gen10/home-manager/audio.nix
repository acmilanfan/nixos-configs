{ pkgs, lib, ... }:
let
  # One implementation, two modes: --once for manual/keybind use, daemon mode
  # for the systemd service that reacts to every Speaker control change.
  speakerBassSync = pkgs.writeShellScriptBin "speaker-bass-sync" (
    lib.readFile ../configs/speaker-bass-sync.sh
  );

  syncVolume = pkgs.writeShellScriptBin "sync-volume" ''
    exec ${speakerBassSync}/bin/speaker-bass-sync --once
  '';

  changeVolume = pkgs.writeShellScriptBin "change-volume" (lib.readFile ../configs/change-volume.sh);
in
{
  home.packages = [
    speakerBassSync
    syncVolume
    changeVolume
  ];

  systemd.user.services.speaker-bass-sync = {
    Unit = {
      Description = "Keep the Yoga Book bass speaker in sync with the main speaker";
      After = [
        "pipewire.service"
        "wireplumber.service"
      ];
    };
    Service = {
      ExecStart = "${speakerBassSync}/bin/speaker-bass-sync";
      Restart = "on-failure";
      RestartSec = 2;
      # The script uses amixer/alsactl, stdbuf/mktemp and gawk.
      Environment = "PATH=${
        lib.makeBinPath [
          pkgs.alsa-utils
          pkgs.coreutils
          pkgs.gawk
        ]
      }:/run/current-system/sw/bin";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
