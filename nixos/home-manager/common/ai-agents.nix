{ config, secrets, ... }:
let
  isWork = config.home.username == "andreishumailov";

  workMarketplaceName = secrets.claude.workMarketplaceName or "";
  workMarketplaceRepo = secrets.claude.workMarketplaceRepo or "";

  # Common hooks to trigger SketchyBar and tmux state
  mkHooks = agent: {
    Notification = [
      {
        hooks = [
          {
            type = "command";
            command = "agent-state --agent ${agent} --state needs-input";
          }
        ];
      }
    ];
    Stop = [
      {
        hooks = [
          {
            type = "command";
            command = "agent-state --agent ${agent} --state done";
          }
        ];
      }
    ];
    PreToolUse = [
      {
        hooks = [
          {
            type = "command";
            command = "agent-state --agent ${agent} --state running";
          }
        ];
      }
    ];
  };

  # Gemini specific hooks (matching the peon-ping example structure)
  geminiHooks = {
    Notification = [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            command = "agent-state --agent gemini --state needs-input";
          }
        ];
      }
    ];
    AfterAgent = [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            command = "agent-state --agent gemini --state done";
          }
        ];
      }
    ];
    AfterTool = [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            command = "agent-state --agent gemini --state done";
          }
        ];
      }
    ];
  };

  claudeSettings = {
    apiKeyHelper = "echo $ANTHROPIC_API_KEY";
    env = {
      ENABLE_LSP_TOOL = "1";
      DISABLE_TELEMETRY = "1";
      DISABLE_BUG_COMMAND = "1";
      DISABLE_ERROR_REPORTING = "1";
    };
    permissions = {
      allow = [ "Bash(mkdir:*)" ];
      deny = [
        "Read(./.env)"
        "Read(./.env.*)"
        "Read(./secrets/**)"
        "Read(~/.aws/**)"
        "Read(~/.zshrc)"
        "Read(~/.bashrc)"
        "Bash(npm:*)"
        "Bash(npx:*)"
      ];
      ask = [ ];
    };
    model = "opus";
    enabledPlugins = {
      "jdtls-lsp@claude-plugins-official" = true;
      "clangd-lsp@claude-plugins-official" = true;
      "lua-lsp@claude-plugins-official" = true;
    } // (if isWork && workMarketplaceName != "" then {
      "check-setup@${workMarketplaceName}" = true;
      "coding-java@${workMarketplaceName}" = true;
      "jdtls-java@${workMarketplaceName}" = true;
    } else {});

    extraKnownMarketplaces = if isWork && workMarketplaceName != "" then {
      "${workMarketplaceName}" = {
        source = {
          source = "github";
          repo = workMarketplaceRepo;
        };
      };
    } else {};

    hooks = mkHooks "claude";
  };

  geminiSettings = {
    security = {
      auth = {
        selectedType = "oauth-personal";
      };
    };
    general = {
      vimMode = true;
      previewFeatures = true;
      sessionRetention = {
        enabled = true;
      };
    };
    hooks = geminiHooks;
  };
in
{
  home.file.".claude/settings.json".text = builtins.toJSON claudeSettings;
  home.file.".gemini/settings.json".text = builtins.toJSON geminiSettings;
}

