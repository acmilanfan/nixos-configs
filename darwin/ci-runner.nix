{ config, lib, pkgs, inputs, unstable, ... }:

let
  cfg = config.services.ciRunner;
  ciUser = "weekenduo-ci";
  ciHome = "/Users/${ciUser}";
  profileBin = "/etc/profiles/per-user/${ciUser}/bin";
  backendToken = config.sops.placeholder."gitlab_runner/backend_token";
  frontendToken = config.sops.placeholder."gitlab_runner/frontend_token";
  nightlyPowerGuard = pkgs.writeShellScriptBin "nightly-power-guard" ''
    set -u

    state_dir="${ciHome}/.cache/weekenduo-ci"
    pid_file="$state_dir/nightly-power-guard.pid"
    log_file="${ciHome}/Library/Logs/nightly-power-guard.log"
    threshold="${toString cfg.batteryMin}"

    /bin/mkdir -p "$state_dir" "$(/usr/bin/dirname "$log_file")"

    log() {
      /bin/echo "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ) $*" >> "$log_file"
    }

    is_running() {
      [ -f "$pid_file" ] && /bin/kill -0 "$(/bin/cat "$pid_file")" 2>/dev/null
    }

    stop() {
      if is_running; then
        pid="$(/bin/cat "$pid_file")"
        if /bin/ps -p "$pid" -o comm= | /usr/bin/grep -q caffeinate; then
          /bin/kill "$pid" 2>/dev/null || true
          i=0
          while /bin/kill -0 "$pid" 2>/dev/null && [ "$i" -lt 5 ]; do
            /bin/sleep 1
            i=$((i + 1))
          done
          log "stopped caffeinate pid=$pid"
        else
          log "pid $pid is not caffeinate; not killing it"
        fi
      fi
      /bin/rm -f "$pid_file"
    }

    read_battery() {
      battery="$(/usr/bin/pmset -g batt)"
      percent="$(/bin/echo "$battery" | /usr/bin/grep -o '[0-9][0-9]*%' | /usr/bin/head -n 1 | /usr/bin/tr -d '%')"
      if /bin/echo "$battery" | /usr/bin/grep -q "AC Power"; then
        source="AC"
      else
        source="battery"
      fi
    }

    if [ "$#" -eq 0 ]; then
      /bin/echo "usage: $0 start|stop|status" >&2
      exit 2
    fi

    case "$1" in
      start)
        if is_running; then
          log "already running pid=$(/bin/cat "$pid_file")"
          exit 0
        fi
        read_battery
        percent_display="$percent"
        [ -n "$percent_display" ] || percent_display="unknown"
        if [ "$source" = "battery" ]; then
          if [ -z "$percent" ]; then
            log "refusing nightly run: cannot read battery percentage"
            /usr/bin/logger -t nightly-power-guard "refusing nightly run: cannot read battery"
            exit 1
          fi
          if [ "$percent" -lt "$threshold" ]; then
            log "refusing nightly run: battery $percent% below ${toString cfg.batteryMin}%"
            /usr/bin/logger -t nightly-power-guard "refusing nightly run: battery $percent% below ${toString cfg.batteryMin}%"
            exit 1
          fi
        fi
        /usr/bin/caffeinate -imsu -t 7200 >> "$log_file" 2>&1 &
        pid=$!
        /bin/echo "$pid" > "$pid_file"
        log "started caffeinate pid=$pid source=$source battery=$percent_display%"
        ;;
      stop)
        stop
        ;;
      status)
        read_battery
        percent_display="$percent"
        [ -n "$percent_display" ] || percent_display="unknown"
        /bin/echo "source=$source battery=$percent_display% threshold=$threshold%"
        ;;
      *)
        /bin/echo "usage: $0 start|stop|status" >&2
        exit 2
        ;;
    esac
  '';
  powerGuardStart = "if [ \"$CI_PIPELINE_SOURCE\" = \"schedule\" ] && [ \"$WD_CI_E2E\" = \"full\" ]; then ${nightlyPowerGuard}/bin/nightly-power-guard start || exit 1; fi; ";
  powerGuardStop = "if [ \"$CI_PIPELINE_SOURCE\" = \"schedule\" ] && [ \"$WD_CI_E2E\" = \"full\" ]; then ${nightlyPowerGuard}/bin/nightly-power-guard stop || true; fi";
  runnerConfig = ''
    concurrent = 2
    check_interval = 3
    shutdown_timeout = 420

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
      pre_build_script = '${powerGuardStart}if ! /etc/profiles/per-user/weekenduo-ci/bin/colima status >/dev/null 2>&1; then lock="/Users/weekenduo-ci/.colima-autostart.lock"; while ! /bin/mkdir "$lock" 2>/dev/null; do /bin/sleep 1; done; trap "/bin/rmdir \"$lock\"" EXIT; if ! /etc/profiles/per-user/weekenduo-ci/bin/colima status >/dev/null 2>&1; then /etc/profiles/per-user/weekenduo-ci/bin/colima start --cpu 8 --memory 16 --disk 60 --activate=false; fi; /bin/rmdir "$lock"; trap - EXIT; fi; DOCKER_HOST=unix:///Users/weekenduo-ci/.colima/default/docker.sock /etc/profiles/per-user/weekenduo-ci/bin/docker info >/dev/null'
      post_build_script = '${powerGuardStop}'
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
      pre_build_script = '${powerGuardStart}if ! /etc/profiles/per-user/weekenduo-ci/bin/colima status >/dev/null 2>&1; then lock="/Users/weekenduo-ci/.colima-autostart.lock"; while ! /bin/mkdir "$lock" 2>/dev/null; do /bin/sleep 1; done; trap "/bin/rmdir \"$lock\"" EXIT; if ! /etc/profiles/per-user/weekenduo-ci/bin/colima status >/dev/null 2>&1; then /etc/profiles/per-user/weekenduo-ci/bin/colima start --cpu 8 --memory 16 --disk 60 --activate=false; fi; /bin/rmdir "$lock"; trap - EXIT; fi; DOCKER_HOST=unix:///Users/weekenduo-ci/.colima/default/docker.sock /etc/profiles/per-user/weekenduo-ci/bin/docker info >/dev/null'
      post_build_script = '${powerGuardStop}'
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
    batteryMin = lib.mkOption {
      type = lib.types.ints.between 0 100;
      default = 30;
      description = "Minimum battery percentage for a scheduled full run when not on AC.";
    };
    wakeTime = lib.mkOption {
      type = lib.types.strMatching "([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]";
      default = "02:45:00";
      description = "Local time for the recurring pmset wake before the nightly full run.";
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
        ] ++ [ pkgs.gitlab-runner nightlyPowerGuard ];
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
          ProcessType = "Standard";
          ThrottleInterval = 10;
          StandardOutPath = "${ciHome}/Library/Logs/gitlab-runner.log";
          StandardErrorPath = "${ciHome}/Library/Logs/gitlab-runner.error.log";
        };
      };

      # Re-apply the RTC wake at boot. pmset persists the repeating event, but
      # a fresh or repaired host needs the schedule installed once.
      launchd.daemons."local.weekenduo-ci-wake" = {
        script = ''
          exec /usr/bin/pmset repeat wakeorpoweron MTWRFSU ${cfg.wakeTime}
        '';
        serviceConfig = {
          RunAtLoad = true;
          KeepAlive = false;
          ProcessType = "Background";
          StandardOutPath = "/var/log/org.nixos.local.weekenduo-ci-wake.log";
          StandardErrorPath = "/var/log/org.nixos.local.weekenduo-ci-wake.error.log";
        };
      };

      # /run/secrets is root-only, so a symlink in the CI home is unreadable
      # by weekenduo-ci. Copy the rendered config to a real owned file whenever
      # a new secret generation appears, then restart the runner.
      launchd.daemons."local.weekenduo-ci-config" = {
        script = ''
          i=0
          while [ ! -s /run/secrets/rendered/gitlab-runner-config ] && [ "$i" -lt 150 ]; do
            /bin/sleep 2
            i=$((i + 1))
          done
          if [ -s /run/secrets/rendered/gitlab-runner-config ]; then
            /usr/bin/install -d -m 0700 -o ${ciUser} -g staff ${ciHome}/.gitlab-runner
            /usr/bin/install -m 0600 -o ${ciUser} -g staff \
              /run/secrets/rendered/gitlab-runner-config \
              ${ciHome}/.gitlab-runner/config.toml.new
            /bin/mv -f ${ciHome}/.gitlab-runner/config.toml.new \
              ${ciHome}/.gitlab-runner/config.toml
            /bin/launchctl kickstart -k system/org.nixos.local.weekenduo-ci-runner 2>/dev/null || true
          fi
        '';
        serviceConfig = {
          RunAtLoad = true;
          KeepAlive = false;
          ProcessType = "Background";
          WatchPaths = [ "/run/secrets.d" ];
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
        # Subshell: a bare umask would leak into the rest of postActivation.
        (
          umask 077
          ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key \
            -i /etc/ssh/ssh_host_ed25519_key > /var/lib/sops-nix/age.key
        )
        /bin/chmod 600 /var/lib/sops-nix/age.key

        /usr/bin/install -d -m 0700 -o ${ciUser} -g staff \
          ${ciHome}/.gitlab-runner ${ciHome}/ci-builds ${ciHome}/ci-cache \
          ${ciHome}/ai ${ciHome}/ai/artifacts ${ciHome}/Library/Logs
        /usr/sbin/chown -R ${ciUser}:staff ${ciHome}/ai

        # Best-effort marker for older macOS. Current macOS ignores it for
        # subfolders, so also add the CI home to Spotlight Search Privacy; see
        # docs/ci-runner-setup.md. Without that, mds_stores can saturate the host.
        for p in ${ciHome} ${ciHome}/ci-builds ${ciHome}/ci-cache \
                 ${ciHome}/ai ${ciHome}/.gitlab-runner ${ciHome}/Library; do
          /usr/bin/touch "$p/.metadata_never_index"
          /usr/sbin/chown ${ciUser}:staff "$p/.metadata_never_index"
        done
      '';
    })

    # A disabled rebuild removes the old LaunchAgent from the earlier design and
    # the system daemon if a previous generation installed it. The account stays.
    (lib.mkIf (!cfg.enable) {
      system.activationScripts.postActivation.text = lib.mkBefore ''
        /bin/launchctl bootout system/org.nixos.local.weekenduo-ci-runner 2>/dev/null || true
        /bin/launchctl bootout system/org.nixos.local.weekenduo-ci-config 2>/dev/null || true
        /bin/launchctl bootout system/org.nixos.local.weekenduo-ci-wake 2>/dev/null || true
        /bin/rm -f /Library/LaunchDaemons/org.nixos.local.weekenduo-ci-runner.plist
        /bin/rm -f /Library/LaunchDaemons/org.nixos.local.weekenduo-ci-config.plist
        /bin/rm -f /Library/LaunchDaemons/org.nixos.local.weekenduo-ci-wake.plist
        # The repeating pmset wake persists; remove it with `pmset repeat cancel`
        # if this host no longer runs nightly jobs.
        if uid=$(/usr/bin/id -u ${ciUser} 2>/dev/null); then
          /bin/launchctl bootout "gui/$uid/org.nixos.local.weekenduo-ci-runner" 2>/dev/null || true
          /bin/rm -f "${ciHome}/Library/LaunchAgents/org.nixos.local.weekenduo-ci-runner.plist"
        fi
      '';
    })
  ];
}
