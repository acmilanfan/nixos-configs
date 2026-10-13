# Agent workflow tooling borrowed from t3code: worktree cleanup, PR watcher,
# per-worktree ports, task-named worktrees, one skills folder for all agents.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (pkgs.stdenv) isDarwin isLinux;
  home = config.home.homeDirectory;

  wtPrune = pkgs.writeShellApplication {
    name = "wt-prune";
    runtimeInputs = [ pkgs.git ];
    text = lib.readFile ./scripts/wt-prune;
  };

  prWatch = pkgs.writeShellApplication {
    name = "pr-watch";
    runtimeInputs = [ pkgs.gh pkgs.jq ];
    text = lib.readFile ./scripts/pr-watch;
  };

  # timeout(1) from coreutils: macOS has none
  aiBranchName = pkgs.writeShellApplication {
    name = "ai-branch-name";
    runtimeInputs = [ pkgs.coreutils pkgs.git ];
    text = lib.readFile ./scripts/ai-branch-name;
  };

  # One skills folder for every agent: Claude Code reads ~/.claude/skills,
  # and opencode reads the same folder as "Claude-compatible" skills. Skills
  # kept in this repo are placed there as real folders (recursive), next to
  # personal ones written there directly.
  repoSkills = ../../../dotfiles/agent-skills;
  skillNames = lib.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir repoSkills));

  # launchd/systemd start with a bare PATH; agent-checkpoint, tmux and the
  # system ssh (keychain, ~/.ssh/config host aliases) live in these
  jobPath = lib.concatStringsSep ":" (lib.unique [
    "/etc/profiles/per-user/${config.home.username}/bin"
    "${config.home.profileDirectory}/bin"
    "/run/current-system/sw/bin"
    "/usr/bin"
    "/bin"
  ]);
  cleanupLog = "${home}/Library/Logs/agent-cleanup.log";
in
{
  home.packages = [ wtPrune prWatch aiBranchName ];

  home.file = lib.listToAttrs (map (name: {
    name = ".claude/skills/${name}";
    value = {
      source = "${repoSkills}/${name}";
      recursive = true;
    };
  }) skillNames);

  # Weekly: remove squash-merged / long-idle empty worktrees, drop agent
  # checkpoints idle for 14 days. `wt-prune` alone is a dry run.
  launchd.agents.agent-cleanup = lib.mkIf isDarwin {
    enable = true;
    config = {
      Label = "agent-cleanup";
      ProgramArguments = [ "${wtPrune}/bin/wt-prune" "--apply" ];
      # Monday 10:00; launchd runs a missed slot at the next wake
      StartCalendarInterval = [ { Weekday = 1; Hour = 10; Minute = 0; } ];
      ProcessType = "Background";
      LowPriorityIO = true;
      EnvironmentVariables.PATH = jobPath;
      StandardOutPath = cleanupLog;
      StandardErrorPath = cleanupLog;
    };
  };

  systemd.user.services.agent-cleanup = lib.mkIf isLinux {
    Unit.Description = "Remove finished git worktrees and old agent checkpoints";
    Service = {
      Type = "oneshot";
      ExecStart = "${wtPrune}/bin/wt-prune --apply";
      Environment = [ "PATH=${jobPath}" ];
      Nice = 10;
    };
  };
  systemd.user.timers.agent-cleanup = lib.mkIf isLinux {
    Unit.Description = "Weekly agent worktree cleanup";
    Timer = {
      OnCalendar = "Mon 10:00";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
