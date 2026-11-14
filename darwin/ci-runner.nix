{ config, lib, pkgs, inputs, unstable, ... }:

let
  cfg = config.services.ciRunner;
  ciUser = "weekenduo-ci";
  ciHome = "/Users/${ciUser}";
  profileBin = "/etc/profiles/per-user/${ciUser}/bin";
  backendToken = config.sops.placeholder."gitlab_runner/backend_token";
  frontendToken = config.sops.placeholder."gitlab_runner/frontend_token";
  runnerConfig = ''
    concurrent = 1
    check_interval = 3
    shutdown_timeout = 30

    [[runners]]
      name = "weekenduo-laptop-backend"
      url = "https://gitlab.com"
      token = "${backendToken}"
      executor = "shell"
      shell = "bash"
      builds_dir = "${ciHome}/ci-builds"
      cache_dir = "${ciHome}/ci-cache"
      environment = [
        "PATH=${profileBin}:/usr/bin:/bin:/usr/sbin:/sbin",
        "DOCKER_HOST=unix://${ciHome}/.colima/default/docker.sock",
        "TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock",
        "WD_CI_STATUS_ENABLE=1"
      ]
      pre_build_script = 'if ! /etc/profiles/per-user/weekenduo-ci/bin/colima status >/dev/null 2>&1; then /etc/profiles/per-user/weekenduo-ci/bin/colima start --cpu 6 --memory 12 --disk 60 --activate=false; fi; DOCKER_HOST=unix:///Users/weekenduo-ci/.colima/default/docker.sock /etc/profiles/per-user/weekenduo-ci/bin/docker info >/dev/null'
      [runners.custom_build_dir]
        enabled = false

    [[runners]]
      name = "weekenduo-laptop-frontend"
      url = "https://gitlab.com"
      token = "${frontendToken}"
      executor = "shell"
      shell = "bash"
      builds_dir = "${ciHome}/ci-builds"
      cache_dir = "${ciHome}/ci-cache"
      environment = [
        "PATH=${profileBin}:/usr/bin:/bin:/usr/sbin:/sbin",
        "DOCKER_HOST=unix://${ciHome}/.colima/default/docker.sock",
        "TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock",
        "WD_CI_STATUS_ENABLE=1"
      ]
      pre_build_script = 'if ! /etc/profiles/per-user/weekenduo-ci/bin/colima status >/dev/null 2>&1; then /etc/profiles/per-user/weekenduo-ci/bin/colima start --cpu 6 --memory 12 --disk 60 --activate=false; fi; DOCKER_HOST=unix:///Users/weekenduo-ci/.colima/default/docker.sock /etc/profiles/per-user/weekenduo-ci/bin/docker info >/dev/null'
      [runners.custom_build_dir]
        enabled = false
  '';
in
{
  imports = [ inputs.sops-nix.darwinModules.sops ];

  options.services.ciRunner = {
    enable = lib.mkEnableOption "the Nix-managed weekenduo-ci GitLab runner daemon";
    uid = lib.mkOption {
      type = lib.types.int;
      default = 599;
      description = "UID for the hidden headless weekenduo-ci service account.";
    };
  };

  config = lib.mkMerge [
    # The account is Nix-managed even while the runner is disabled. Do not add
    # it to users.knownUsers unless you accept that removing it later deletes
    # the account and home directory.
    {
      assertions = [
        {
          assertion = config.system.primaryUser != ciUser;
          message = "services.ciRunner must not use the primary desktop user.";
        }
        {
          assertion = cfg.uid >= 501;
          message = "services.ciRunner.uid must be a non-system UID (>= 501).";
        }
      ];
      users.knownUsers = [ ciUser ];
      users.users.${ciUser} = {
        uid = cfg.uid;
        gid = 20;
        home = ciHome;
        createHome = true;
        isHidden = true;
        description = "Weekenduo local CI runner";
        shell = "/bin/bash";
        packages = with unstable; [
          nodejs_22
          go
          git
          curl
          docker
          colima
        ] ++ [ pkgs.gitlab-runner ];
      };
    }

    (lib.mkIf cfg.enable {
      launchd.daemons."local.weekenduo-ci-runner" = {
        environment = {
          HOME = ciHome;
          PATH = "${profileBin}:/usr/bin:/bin:/usr/sbin:/sbin";
        };
        script = ''
          exec ${pkgs.gitlab-runner}/bin/gitlab-runner run --config ${ciHome}/.gitlab-runner/config.toml
        '';
        serviceConfig = {
          UserName = ciUser;
          GroupName = "staff";
          WorkingDirectory = ciHome;
          RunAtLoad = true;
          KeepAlive = true;
          ProcessType = "Background";
          ThrottleInterval = 10;
          StandardOutPath = "${ciHome}/Library/Logs/gitlab-runner.log";
          StandardErrorPath = "${ciHome}/Library/Logs/gitlab-runner.error.log";
        };
      };

      sops = {
        defaultSopsFile = ../secrets/secrets.yaml;
        defaultSopsFormat = "yaml";
        validateSopsFiles = false;
        # sops' native SOPS_AGE_SSH_PRIVATE_KEY_FILE path is broken for the
        # ssh-to-age recipient; derive a root-only age key file instead.
        age.keyFile = "/var/lib/sops-nix/age.key";
        age.sshKeyPaths = lib.mkForce [ ];
        age.sshKeyFile = lib.mkForce null;
        gnupg.sshKeyPaths = lib.mkForce [ ];

        secrets = {
          "gitlab_runner/backend_token" = {
            owner = ciUser;
            mode = "0400";
          };
          "gitlab_runner/frontend_token" = {
            owner = ciUser;
            mode = "0400";
          };
        };

        templates."gitlab-runner-config" = {
          path = "${ciHome}/.gitlab-runner/config.toml";
          owner = ciUser;
          mode = "0600";
          content = runnerConfig;
        };
      };

      # The user exists from the users activation script; sops installs later
      # in postActivation, so create the owned directories before it runs.
      system.activationScripts.postActivation.text = lib.mkBefore ''
        /usr/bin/install -d -m 0700 -o root -g wheel /var/lib/sops-nix
        umask 077
        ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key \
          -i /etc/ssh/ssh_host_ed25519_key > /var/lib/sops-nix/age.key
        /bin/chmod 600 /var/lib/sops-nix/age.key

        /usr/bin/install -d -m 0700 -o ${ciUser} -g staff \
          ${ciHome}/.gitlab-runner ${ciHome}/ci-builds ${ciHome}/ci-cache \
          ${ciHome}/ai ${ciHome}/ai/artifacts ${ciHome}/Library/Logs
        /usr/sbin/chown -R ${ciUser}:staff ${ciHome}/ai
      '';
    })

    # A disabled rebuild removes the old LaunchAgent from the earlier design and
    # the system daemon if a previous generation installed it. The account stays.
    (lib.mkIf (!cfg.enable) {
      system.activationScripts.postActivation.text = lib.mkBefore ''
        /bin/launchctl bootout system/org.nixos.local.weekenduo-ci-runner 2>/dev/null || true
        /bin/rm -f /Library/LaunchDaemons/org.nixos.local.weekenduo-ci-runner.plist
        if uid=$(/usr/bin/id -u ${ciUser} 2>/dev/null); then
          /bin/launchctl bootout "gui/$uid/org.nixos.local.weekenduo-ci-runner" 2>/dev/null || true
          /bin/rm -f "${ciHome}/Library/LaunchAgents/org.nixos.local.weekenduo-ci-runner.plist"
        fi
      '';
    })
  ];
}
