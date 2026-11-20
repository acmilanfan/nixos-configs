{ pkgs }:
let
  mk =
    name: runtimeInputs: path:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = builtins.readFile path;
    };

  diskGuard = mk "weekenduo-ci-disk-guard" [ pkgs.coreutils pkgs.gawk ] ./disk-guard.sh;
  powerGuard = mk "weekenduo-ci-power-guard" [ pkgs.coreutils pkgs.gawk ] ./power-guard.sh;
in
{
  prepare = mk "weekenduo-ci-prepare" [ pkgs.coreutils pkgs.gnused ] ./prepare.sh;
  preBuild = mk "weekenduo-ci-pre-build" [
    pkgs.coreutils
    pkgs.gawk
    pkgs.docker-client
    diskGuard
    powerGuard
  ] ./pre-build.sh;
  postBuild = mk "weekenduo-ci-post-build" [ pkgs.coreutils ] ./post-build.sh;
  recordDocker = mk "weekenduo-ci-record-docker" [ pkgs.coreutils pkgs.docker-client ] ./record-docker.sh;
  inherit diskGuard powerGuard;
}
