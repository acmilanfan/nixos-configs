{ config, lib, pkgs, unstable, ... }:
let
  cfg = config.services.localCiStatus;
  bar = unstable.callPackage ../../common/pkgs/sketchybar { };
  helper = pkgs.writeShellApplication {
    name = "local-ci-status";
    runtimeInputs = [ bar ];
    text = ''
      export PYTHONDONTWRITEBYTECODE=1
      exec ${pkgs.python3}/bin/python3 ${./local-ci-status} "$@"
    '';
  };
in
{
  options.services.localCiStatus = {
    enable = lib.mkEnableOption "desktop observation of explicit local CI/E2E records";
    ciUser = lib.mkOption {
      type = lib.types.strMatching "[a-z_][a-z0-9_-]*";
      default = "weekenduo-ci";
      description = "Only this optional account and the login UID may publish records.";
    };
    interval = lib.mkOption {
      type = lib.types.ints.between 1 60;
      default = 3;
      description = "Elapsed-time and crash reconciliation interval in seconds, only while runs are active.";
    };
    finalizationGraceSeconds = lib.mkOption {
      type = lib.types.ints.between 1 300;
      default = 15;
      description = "Grace for a dead owner to publish an explicit terminal result.";
    };
    successSeconds = lib.mkOption {
      type = lib.types.ints.between 1 300;
      default = 30;
      description = "Duration of the successful-result highlight.";
    };
    allowedProjects = lib.mkOption {
      type = lib.types.listOf (lib.types.enum [ "weekenduo/backend" "weekenduo/duomobile" ]);
      default = [ "weekenduo/backend" "weekenduo/duomobile" ];
      description = "Allowed GitLab projects; job URLs are independently validated.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = helper;
      description = "Noninteractive desktop observer helper.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{ assertion = pkgs.stdenv.isDarwin; message = "localCiStatus requires the macOS desktop."; }];
    home.packages = [ helper ];
    home.file = {
      ".config/local-ci-status/enabled".text = "1\n";
      ".config/local-ci-status/config.json".text = builtins.toJSON {
        inherit (cfg) ciUser interval finalizationGraceSeconds successSeconds allowedProjects;
        sharedRoot = "/Users/Shared";
        stateDir = "${config.home.homeDirectory}/.cache/local-ci-status";
        enabledFile = "${config.home.homeDirectory}/.config/local-ci-status/enabled";
        helperCommand = "${helper}/bin/local-ci-status";
      };
      ".config/sketchybar/plugins/ci_status.sh" = {
        source = ../../../dotfiles/sketchybar/plugins/ci_status.sh;
        executable = true;
      };
    };
  };
}
