# Common sops-nix configuration for home-manager
# Decrypts secrets at activation/runtime using GPG without leaking plain secrets
# to /nix/store or git history.
{
  config,
  lib,
  pkgs,
  secrets,
  inputs ? { },
  ...
}:

let
  hasSopsNix = inputs ? sops-nix;

  # Work MCP credentials (sops key -> env var), present only for the services
  # configured in secrets.work.mcp.
  workMcp = import ./work-mcp.nix { inherit lib pkgs secrets; };

  # Path to encrypted secrets file in secrets submodule. Only present in the
  # flake source because flake.nix sets `self.submodules = true`.
  secretsFile = ../../../secrets/secrets.yaml;

  # GitHub token for the GitHub MCP servers (GITHUB_PERSONAL_ACCESS_TOKEN):
  # only the work credential can see the wkda org, so it is used on the work
  # machine and the personal one everywhere else.
  githubMcpTokenKey =
    if config.home.username == "andreishumailov" then "github/token" else "github/personal_token";

  # Personal Plane workspace. The slug is a non-secret identifier from
  # secrets.nix; its presence enables the Plane MCP server and CLI env vars.
  planeSlug = (secrets.plane or { }).workspaceSlug or "";

  # ai-env.sh line that sets shell variable `var` from the sops secret `key`
  # when it is sourced. Reading the file, rather than pasting the value into
  # the template, leaves a value containing $, ` or quotes uninterpreted.
  # `read` is a builtin in zsh and bash, so the many shells that source this
  # fork nothing; it returns non-zero at the missing trailing newline but has
  # set the variable by then.
  readSecret = var: key:
    ''${var}=""; IFS= read -r ${var} 2>/dev/null < ${lib.escapeShellArg config.sops.secrets.${key}.path} || true'';

  cfg = config.customSops;
in
{
  imports = lib.optional hasSopsNix inputs.sops-nix.homeManagerModules.sops;

  options.customSops = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable SOPS secret management via sops-nix.";
    };

    secretsFile = lib.mkOption {
      type = lib.types.path;
      default = secretsFile;
      description = "Path to the encrypted secrets.yaml file.";
    };
  };

  config = lib.mkIf (hasSopsNix && cfg.enable) {
    # Fail loudly instead of silently rendering nothing (the old pathExists
    # gate was false whenever the submodule wasn't in the flake source).
    assertions = [
      {
        assertion = builtins.pathExists cfg.secretsFile;
        message = "customSops: ${toString cfg.secretsFile} is missing; check out the secrets submodule.";
      }
    ];

    # sops-nix's own activation entry (launchctl bootstrap of its agent plist /
    # systemctl restart of its unit) is unordered. On a first switch it can run
    # before HM has written the plist/unit, fail ("Bootstrap failed: 5") and
    # abort the rest of activation. This entry merges into it, adding only the
    # ordering (mkDefault data, so sops-nix's own script wins).
    home.activation.sops-nix = {
      data = lib.mkDefault "";
      after = if pkgs.stdenv.hostPlatform.isDarwin then [ "setupLaunchAgents" ] else [ "reloadSystemd" ];
      before = [ ];
    };

    # .zshenv, not .zshrc: non-interactive shells (`zsh -lc nvim` from
    # nvim-opener, scripts) need the AI proxy keys too.
    programs.zsh.envExtra = ''
      [ -r "${config.sops.templates."ai-env.sh".path}" ] && . "${config.sops.templates."ai-env.sh".path}"
    '';

    # Nix does not use GITHUB_PERSONAL_ACCESS_TOKEN automatically. Include a
    # runtime-rendered config so flake updates authenticate without placing
    # the token in the generated, world-readable nix.conf in /nix/store.
    nix = {
      package = lib.mkDefault pkgs.nix;
      extraOptions = ''
        !include ${config.sops.templates."nix-github.conf".path}
      '';
    };

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
        "context7/apiKey" = { };
        # Work credential (wkda access): GitHub MCP on the work machine.
        "github/token" = { };
        # Personal-account credential: Nix downloads, and the GitHub MCP
        # off the work machine.
        "github/personal_token" = { };
        "sonar/apiKey" = { };
        "sonar/url" = { };
        "mcp/ragUrl" = { };
        "mcp/scorecardUrl" = { };

        # System services
        "syncthing_api_key" = { };
        "obsWebsocketPassword" = { };
      } // lib.mapAttrs (_: _: { }) workMcp.credentials
      # Personal Plane token: only declared when the workspace slug is
      # configured, so older secrets checkouts still evaluate.
      // lib.optionalAttrs (planeSlug != "") {
        "plane/apiKey" = { };
      };

      templates = {
        # Published atomically with the secret generation. Consumers can wait
        # for this ciphertext fingerprint instead of accepting an existing,
        # possibly stale secret file while launchd is still decrypting.
        "mcp-credentials-generation" = {
          content = builtins.hashFile "sha256" cfg.secretsFile;
        };

        "nix-github.conf" = {
          mode = "0600";
          content = ''
            extra-access-tokens = github.com=${config.sops.placeholder."github/personal_token"}
          '';
        };

        # Sourced from .zshenv (above) and the opencode-serve launcher: exports
        # API keys into user sessions without storing any secret values in
        # /nix/store. Read by avante/minuet (nvim) and opencode's providers.
        "ai-env.sh" = {
          mode = "0600";
          content = ''
            ${readSecret "AI_PROXY_CLAUDE" "aiProxy/claude"}; export AI_PROXY_CLAUDE
            ${readSecret "AI_PROXY_OPENAI" "aiProxy/openai"}; export AI_PROXY_OPENAI
            ${readSecret "AI_PROXY_MISTRAL_COMPLETION" "aiProxy/mistralCompletion"}; export AI_PROXY_MISTRAL_COMPLETION
            ${readSecret "AI_PROXY_API_KEY" "aiProxy/apiKey"}; export AI_PROXY_API_KEY
            # Empty selfHosted* (hosts that never had the key) fall back to the
            # Claude endpoint / shared proxy key, as the old Nix-side default did.
            ${readSecret "SELF_HOSTED_BASE_URL" "aiProxy/selfHosted"}
            # Prefix/suffix expansion, not ''${var//a/b}: zsh keeps the
            # backslashes of escaped slashes in the replacement.
            if [ -z "$SELF_HOSTED_BASE_URL" ]; then
              case "$AI_PROXY_CLAUDE" in
                */proxy-api/anthropic*) SELF_HOSTED_BASE_URL="''${AI_PROXY_CLAUDE%%/proxy-api/anthropic*}/proxy-api/self-hosted/v1''${AI_PROXY_CLAUDE#*/proxy-api/anthropic}" ;;
                *) SELF_HOSTED_BASE_URL="$AI_PROXY_CLAUDE" ;;
              esac
            fi
            ${readSecret "SELF_HOSTED_API_KEY" "aiProxy/selfHostedKey"}
            [ -n "$SELF_HOSTED_API_KEY" ] || SELF_HOSTED_API_KEY="$AI_PROXY_API_KEY"
            export SELF_HOSTED_BASE_URL SELF_HOSTED_API_KEY
            ${readSecret "CONTEXT7_API_KEY" "context7/apiKey"}; export CONTEXT7_API_KEY
            ${lib.optionalString (planeSlug != "") ''
              ${readSecret "PLANE_API_KEY" "plane/apiKey"}; export PLANE_API_KEY
              export PLANE_WORKSPACE_SLUG="${planeSlug}"
            ''}
            ${readSecret "GITHUB_PERSONAL_ACCESS_TOKEN" githubMcpTokenKey}; export GITHUB_PERSONAL_ACCESS_TOKEN
            ${readSecret "SONAR_API_KEY" "sonar/apiKey"}; export SONAR_API_KEY
            ${readSecret "SONAR_URL" "sonar/url"}; export SONAR_URL
            ${readSecret "RAG_MCP_URL" "mcp/ragUrl"}; export RAG_MCP_URL
            ${readSecret "SCORECARD_MCP_URL" "mcp/scorecardUrl"}; export SCORECARD_MCP_URL
            ${readSecret "OBS_PASSWORD" "obsWebsocketPassword"}; export OBS_PASSWORD
            # Work MCP credentials (work-mcp.nix). An empty value stays unset, so
            # the server reports a missing variable instead of failing auth.
            ${lib.concatStrings (lib.mapAttrsToList (key: env: ''
              ${readSecret "_v" key}; [ -z "$_v" ] || export ${env}="$_v"
            '') workMcp.credentials)}unset _v
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
