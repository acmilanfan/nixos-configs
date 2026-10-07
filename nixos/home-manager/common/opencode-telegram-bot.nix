# opencode-telegram-bot service
#
# Runs the Telegram client for OpenCode (grinev/opencode-telegram-bot) as a
# persistent user service (launchd on macOS, systemd on Linux), plus an optional
# `opencode serve` daemon that keeps the OpenCode HTTP API up on a fixed port.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.services.opencode-telegram-bot;

  opencode = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode;
  servicePath = "${opencode}/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/usr/sbin:/sbin";

  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;

  appDataDir =
    if isDarwin then
      "${config.home.homeDirectory}/Library/Application Support/opencode-telegram-bot"
    else
      "${config.xdg.configHome}/opencode-telegram-bot";

  logDir =
    if isDarwin then
      "${config.home.homeDirectory}/Library/Logs/opencode-telegram-bot"
    else
      "${config.xdg.stateHome}/opencode-telegram-bot/logs";

  envFilePath = "${appDataDir}/.env";

  hasSops = config ? sops && config.sops.secrets ? "telegram/bot_token";
in
{
  options.services.opencode-telegram-bot = {
    enable = lib.mkEnableOption "the opencode-telegram-bot service (launchd on macOS, systemd on Linux)";

    autoStartServer = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Also run a persistent `opencode serve --port <port>` service.
        Off by default: then use /opencode_start in Telegram (the bot spawns
        opencode itself) or run `opencode --port <port>` in a terminal to
        track a live TUI session.
      '';
    };

    serverPort = lib.mkOption {
      type = lib.types.port;
      default = 4096;
      description = "Port where OpenCode server listens.";
    };

    apiUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:${toString cfg.serverPort}";
      description = "URL of the OpenCode API the bot connects to.";
    };

    modelProvider = lib.mkOption {
      type = lib.types.str;
      default = "opencode";
      description = "Default model provider (e.g. opencode, anthropic, openai).";
    };

    modelId = lib.mkOption {
      type = lib.types.str;
      default = "big-pickle";
      description = "Default model ID (e.g. big-pickle, claude-sonnet-4-5).";
    };

    manageEnvWithSops = lib.mkOption {
      type = lib.types.bool;
      default = hasSops;
      defaultText = lib.literalExpression "true if sops has telegram/bot_token";
      description = ''
        Whether to generate the bot's .env file from sops-nix templates.
        When false, the user manages ~/.env manually or runs the wizard.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.opencode-telegram-bot ];

    # Ensure app data & log directories exist
    home.activation.opencodeTelegramDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "${appDataDir}"
      mkdir -p "${logDir}"
    '';

    # Optional automatic .env rendering via sops-nix template
    sops.templates."opencode-telegram-bot.env" = lib.mkIf (cfg.manageEnvWithSops && hasSops) {
      path = envFilePath;
      mode = "0600";
      content = ''
        TELEGRAM_BOT_TOKEN=${config.sops.placeholder."telegram/bot_token"}
        TELEGRAM_ALLOWED_USER_ID=${config.sops.placeholder."telegram/allowed_user_id"}
        OPENCODE_MODEL_PROVIDER=${cfg.modelProvider}
        OPENCODE_MODEL_ID=${cfg.modelId}
        OPENCODE_API_URL=${cfg.apiUrl}
        OPENCODE_TELEGRAM_RUNTIME_MODE=installed
      '';
    };

    # macOS launchd agent
    launchd.agents.opencode-telegram-bot = lib.mkIf isDarwin {
      enable = true;
      config = {
        Label = "opencode-telegram-bot";
        ProgramArguments = [
          "${pkgs.opencode-telegram-bot}/bin/opencode-telegram"
          "start"
        ];
        KeepAlive = true;
        RunAtLoad = true;
        ProcessType = "Background";
        ThrottleInterval = 15; # Avoid tight restart spin loop on error
        EnvironmentVariables = {
          OPENCODE_TELEGRAM_RUNTIME_MODE = "installed";
          PATH = servicePath;
        };
        StandardOutPath = "${logDir}/stdout.log";
        StandardErrorPath = "${logDir}/stderr.log";
      };
    };

    launchd.agents.opencode-server = lib.mkIf (isDarwin && cfg.autoStartServer) {
      enable = true;
      config = {
        Label = "opencode-serve";
        ProgramArguments = [
          "${opencode}/bin/opencode"
          "serve"
          "--port"
          (toString cfg.serverPort)
        ];
        KeepAlive = true;
        RunAtLoad = true;
        ThrottleInterval = 15;
        EnvironmentVariables.PATH = servicePath;
        StandardOutPath = "${logDir}/server.stdout.log";
        StandardErrorPath = "${logDir}/server.stderr.log";
      };
    };

    # Linux systemd user service
    systemd.user.services.opencode-telegram-bot = lib.mkIf isLinux {
      Unit = {
        Description = "Telegram client for OpenCode";
        After = [ "network.target" ];
      };
      Service = {
        ExecStart = "${pkgs.opencode-telegram-bot}/bin/opencode-telegram start";
        Restart = "on-failure";
        RestartSec = "15s";
        Environment = [
          "OPENCODE_TELEGRAM_RUNTIME_MODE=installed"
          "PATH=${servicePath}"
        ];
        StandardOutput = "journal";
        StandardError = "journal";
      };
      Install.WantedBy = [ "default.target" ];
    };

    systemd.user.services.opencode-server = lib.mkIf (isLinux && cfg.autoStartServer) {
      Unit = {
        Description = "OpenCode HTTP server";
        After = [ "network.target" ];
      };
      Service = {
        ExecStart = "${opencode}/bin/opencode serve --port ${toString cfg.serverPort}";
        Restart = "on-failure";
        RestartSec = "15s";
        Environment = [ "PATH=${servicePath}" ];
        StandardOutput = "journal";
        StandardError = "journal";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
