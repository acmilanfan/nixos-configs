{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.services.weekenduoCi;
  ciUser = "weekenduo-ci";
  ciHome = "/home/${ciUser}";
  profileBin = "/etc/profiles/per-user/${ciUser}/bin";
  cypress = inputs.nixpkgs-cypress.legacyPackages.${pkgs.stdenv.hostPlatform.system}.cypress;
  scripts = import ./scripts { inherit pkgs; };
  runnerConfigTemplate = ''
    concurrent = ${toString cfg.concurrent}
    check_interval = 3
    shutdown_timeout = 420

    [[runners]]
      name = "weekenduo-${config.networking.hostName}-backend"
      url = "https://gitlab.com"
      token = "__BACKEND_TOKEN__"
      executor = "shell"
      shell = "bash"
      builds_dir = "${ciHome}/ci-builds"
      cache_dir = "${ciHome}/ci-cache"
      request_concurrency = 2
      environment = [
        "PATH=${profileBin}:/run/current-system/sw/bin",
        "LANG=C.UTF-8",
        "TZ=UTC",
        "DOCKER_HOST=unix:///var/run/docker.sock",
        "TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock",
        "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt",
        "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt",
        "CYPRESS_RUN_BINARY=${cypress}/bin/cypress",
        "CYPRESS_INSTALL_BINARY=0",
        "CYPRESS_CACHE_FOLDER=${ciHome}/.cache/Cypress",
        "COREPACK_HOME=${ciHome}/.cache/corepack",
        "WD_CI_STATUS_ENABLE=0"
      ]
      pre_build_script = "${scripts.preBuild}/bin/weekenduo-ci-pre-build"
      post_build_script = "${scripts.postBuild}/bin/weekenduo-ci-post-build"
      [runners.custom_build_dir]
        enabled = false

    [[runners]]
      name = "weekenduo-${config.networking.hostName}-frontend"
      url = "https://gitlab.com"
      token = "__FRONTEND_TOKEN__"
      executor = "shell"
      shell = "bash"
      builds_dir = "${ciHome}/ci-builds"
      cache_dir = "${ciHome}/ci-cache"
      request_concurrency = 2
      environment = [
        "PATH=${profileBin}:/run/current-system/sw/bin",
        "LANG=C.UTF-8",
        "TZ=UTC",
        "DOCKER_HOST=unix:///var/run/docker.sock",
        "TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock",
        "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt",
        "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt",
        "CYPRESS_RUN_BINARY=${cypress}/bin/cypress",
        "CYPRESS_INSTALL_BINARY=0",
        "CYPRESS_CACHE_FOLDER=${ciHome}/.cache/Cypress",
        "COREPACK_HOME=${ciHome}/.cache/corepack",
        "WD_CI_STATUS_ENABLE=0"
      ]
      pre_build_script = "${scripts.preBuild}/bin/weekenduo-ci-pre-build"
      post_build_script = "${scripts.postBuild}/bin/weekenduo-ci-post-build"
      [runners.custom_build_dir]
        enabled = false
  '';
  templateFile = pkgs.writeText "weekenduo-ci-runner.toml.template" runnerConfigTemplate;
in
{
  options.services.weekenduoCi = {
    enable = lib.mkEnableOption "the Weekenduo Linux GitLab runner";
    concurrent = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = "Maximum concurrent GitLab jobs on this host.";
    };
    keepAwake = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Ignore lid close and idle suspend on AC for an overnight worker.";
    };
    batteryMin = lib.mkOption {
      type = lib.types.ints.between 0 100;
      default = 30;
      description = "Minimum battery percentage for a scheduled full run when not on AC.";
    };
    minFreeGb = lib.mkOption {
      type = lib.types.ints.positive;
      default = 20;
      description = "Minimum free GB on the CI home before a job starts.";
    };
    runnerEnvFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/weekenduo-ci/runner.env";
      description = "Root-only file containing BACKEND_TOKEN and FRONTEND_TOKEN.";
    };
    dockerDataRoot = lib.mkOption {
      type = lib.types.str;
      default = "/home/docker";
      description = "Docker data root for the CI-only daemon.";
    };
    runnerConfigTemplate = lib.mkOption {
      type = lib.types.str;
      default = runnerConfigTemplate;
      readOnly = true;
      internal = true;
      description = "Generated GitLab Runner config with token placeholders; for tests.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.concurrent >= 1;
        message = "services.weekenduoCi.concurrent must be at least 1.";
      }
      {
        assertion = lib.hasPrefix "/" cfg.runnerEnvFile;
        message = "services.weekenduoCi.runnerEnvFile must be an absolute path.";
      }
      {
        assertion = lib.hasPrefix "/home/" cfg.dockerDataRoot;
        message = "services.weekenduoCi.dockerDataRoot must be under /home.";
      }
    ];

    users.groups.${ciUser} = { };
    users.users.${ciUser} = {
      uid = 599;
      isSystemUser = true;
      group = ciUser;
      home = ciHome;
      createHome = true;
      description = "Weekenduo Linux CI runner";
      shell = "${pkgs.bashInteractive}/bin/bash";
      extraGroups = [ "docker" ];
      packages = [
        pkgs.nodejs_22
        pkgs.go
        pkgs.gcc
        pkgs.gnumake
        pkgs.python3
        pkgs.pkg-config
        pkgs.git
        pkgs.curl
        pkgs.gnutar
        pkgs.gzip
        pkgs.cacert
        pkgs.jq
        pkgs.docker-client
        pkgs.iproute2
        pkgs.lsof
        pkgs.procps
        pkgs.gitlab-runner
        cypress
        pkgs.xvfb
        pkgs.xauth
        pkgs.fontconfig
        pkgs.dejavu_fonts
        pkgs.bashInteractive
        pkgs.coreutils
        scripts.recordDocker
      ];
    };

    fonts.packages = [ pkgs.dejavu_fonts ];

    environment.systemPackages = [ scripts.setTokens ];

    virtualisation.docker.enable = true;
    virtualisation.docker.daemon.settings.data-root = cfg.dockerDataRoot;

    systemd.services.docker.unitConfig.RequiresMountsFor = [ "/home" ];

    systemd.tmpfiles.rules = [
      "d ${cfg.dockerDataRoot} 0710 root docker -"
      "d ${ciHome}/ci-builds 0700 ${ciUser} ${ciUser} -"
      "d ${ciHome}/ci-cache 0700 ${ciUser} ${ciUser} -"
      "d ${ciHome}/ai/artifacts 0700 ${ciUser} ${ciUser} -"
      "d /etc/weekenduo-ci 0750 root root -"
    ];

    services.logind.settings = lib.mkIf cfg.keepAwake {
      Login.HandleLidSwitch = "ignore";
      Login.HandleLidSwitchExternalPower = "ignore";
      Login.HandleLidSwitchDocked = "ignore";
      Login.IdleAction = "ignore";
    };

    systemd.services.weekenduo-ci-runner = {
      description = "Weekenduo Linux GitLab runner";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "docker.service" ];
      wants = [ "network-online.target" ];
      requires = [ "docker.service" ];
      environment = {
        HOME = ciHome;
        PATH = lib.mkForce "${profileBin}:/run/current-system/sw/bin";
        DOCKER_HOST = "unix:///var/run/docker.sock";
        WEEKENDUO_CI_HOME = ciHome;
        WEEKENDUO_CI_MIN_FREE_GB = toString cfg.minFreeGb;
        WEEKENDUO_CI_BATTERY_MIN = toString cfg.batteryMin;
        WEEKENDUO_CI_POWER_SUPPLY = "/sys/class/power_supply";
      };
      serviceConfig = {
        User = ciUser;
        Group = ciUser;
        SupplementaryGroups = [ "docker" ];
        WorkingDirectory = ciHome;
        RuntimeDirectory = "weekenduo-ci";
        RuntimeDirectoryMode = "0700";
        LoadCredential = [ "runner-env:${cfg.runnerEnvFile}" ];
        ExecStartPre = "${scripts.prepare}/bin/weekenduo-ci-prepare ${templateFile} /run/weekenduo-ci/config.toml";
        ExecStart = "${pkgs.gitlab-runner}/bin/gitlab-runner run --config /run/weekenduo-ci/config.toml";
        Restart = "always";
        RestartSec = 10;
        KillSignal = "SIGQUIT";
        TimeoutStopSec = "7min";
      };
    };
  };
}
