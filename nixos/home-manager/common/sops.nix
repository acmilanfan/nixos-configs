# Common sops-nix configuration for home-manager
# Decrypts secrets at activation/runtime using GPG without leaking plain secrets
# to /nix/store or git history.
{
  config,
  lib,
  pkgs,
  inputs ? { },
  ...
}:

let
  hasSopsNix = inputs ? sops-nix;

  # Path to encrypted secrets file in secrets submodule
  secretsFile = ../../../secrets/secrets.yaml;
  secretsFileExists = builtins.pathExists secretsFile;

  cfg = config.customSops;
in
{
  imports = lib.optional hasSopsNix inputs.sops-nix.homeManagerModules.sops;

  options.customSops = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = secretsFileExists;
      defaultText = lib.literalExpression "builtins.pathExists ../../../secrets/secrets.yaml";
      description = "Enable SOPS secret management via sops-nix.";
    };

    secretsFile = lib.mkOption {
      type = lib.types.path;
      default = secretsFile;
      description = "Path to the encrypted secrets.yaml file.";
    };
  };

  config = lib.mkIf (hasSopsNix && cfg.enable && secretsFileExists) {
    sops = {
      defaultSopsFile = cfg.secretsFile;
      defaultSopsFormat = "yaml";
      validateSopsFiles = false;

      gnupg.home = "${config.home.homeDirectory}/.gnupg";

      secrets = {
        # Telegram Bot
        "telegram/bot_token" = { };
        "telegram/allowed_user_id" = { };

        # AI Proxy
        "aiProxy/claude" = { };
        "aiProxy/openai" = { };
        "aiProxy/mistralCompletion" = { };
        "aiProxy/apiKey" = { };
        "aiProxy/claudeKey" = { };
        "aiProxy/selfHosted" = { };
        "aiProxy/selfHostedKey" = { };

        # MCP / Developer Tools
        "github/token" = { };
        "sonar/apiKey" = { };
        "sonar/url" = { };
        "mcp/ragUrl" = { };
        "mcp/scorecardUrl" = { };

        # System services
        "syncthing_api_key" = { };
        "obsWebsocketPassword" = { };
      };

      templates = {
        # Sourced in shell.nix: exports API keys into user shell sessions
        # without storing any secret values in /nix/store.
        "ai-env.sh" = {
          mode = "0600";
          content = ''
            export AI_PROXY_CLAUDE="${config.sops.placeholder."aiProxy/claude"}"
            export AI_PROXY_OPENAI="${config.sops.placeholder."aiProxy/openai"}"
            export AI_PROXY_MISTRAL_COMPLETION="${config.sops.placeholder."aiProxy/mistralCompletion"}"
            export AI_API_KEY="${config.sops.placeholder."aiProxy/apiKey"}"
            export SELF_HOSTED_BASE_URL="${config.sops.placeholder."aiProxy/selfHosted"}"
            export SELF_HOSTED_API_KEY="${config.sops.placeholder."aiProxy/selfHostedKey"}"
            export GITHUB_PERSONAL_ACCESS_TOKEN="${config.sops.placeholder."github/token"}"
            export SONAR_API_KEY="${config.sops.placeholder."sonar/apiKey"}"
            export SONAR_URL="${config.sops.placeholder."sonar/url"}"
            export RAG_MCP_URL="${config.sops.placeholder."mcp/ragUrl"}"
            export SCORECARD_MCP_URL="${config.sops.placeholder."mcp/scorecardUrl"}"
            export OBS_PASSWORD="${config.sops.placeholder."obsWebsocketPassword"}"
          '';
        };

        # SyncMon config on Darwin
        "syncmon.yaml" = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
          path = "${config.home.homeDirectory}/.syncmon.yaml";
          mode = "0600";
          content = ''
            syncthing:
              url: "http://127.0.0.1:8384"
              apikey: "${config.sops.placeholder."syncthing_api_key"}"
            paths:
              org: "~/org"
              configs: "~/configs/nixos-configs"
              nextcloud: "~/Nextcloud"
          '';
        };
      };
    };
  };
}
