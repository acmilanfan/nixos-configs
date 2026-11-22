{ pkgs, ... }:

let
  ciStatus = pkgs.writeShellApplication {
    name = "ci-status";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      glab
      gnugrep
      gnused
      iproute2
      jq
      procps
      systemd
    ];
    text = builtins.readFile ./scripts/ci-status.sh;
  };

  ciNotify = pkgs.writeShellApplication {
    name = "ci-notify";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      gnused
      libnotify
      systemd
    ];
    text = builtins.readFile ./scripts/ci-notify.sh;
  };
in
{
  home.packages = [ ciStatus ciNotify ];

  systemd.user.services.ci-notify = {
    Unit.Description = "Weekenduo CI journal notifications";
    Service = {
      ExecStart = "${pkgs.bash}/bin/bash -c 'export DBUS_SESSION_BUS_ADDRESS=unix:path=%t/bus; exec ${ciNotify}/bin/ci-notify'";
      Restart = "always";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
