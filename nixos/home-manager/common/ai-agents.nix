{ config, secrets, pkgs, inputs, lib, ... }:
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
    BeforeTool = [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            command = "agent-state --agent gemini --state running";
          }
        ];
      }
    ];
    BeforeAgent = [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            command = "agent-state --agent gemini --state running";
          }
        ];
      }
    ];
    SessionEnd = [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            command = "agent-state --agent gemini --state off";
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
    model = "opusplan";
    enabledPlugins = {
      "jdtls-lsp@claude-plugins-official" = true;
      "clangd-lsp@claude-plugins-official" = true;
      "lua-lsp@claude-plugins-official" = true;
      "github@claude-plugins-official" = true;
      "code-review@claude-plugins-official" = true;
      "superpowers@claude-plugins-official" = true;
    } // (if isWork && workMarketplaceName != "" then {
      "check-setup@${workMarketplaceName}" = true;
      "coding-java@${workMarketplaceName}" = true;
      "jdtls-java@${workMarketplaceName}" = true;
      "global-skills@${workMarketplaceName}" = true;
      "scorecard@${workMarketplaceName}" = true;
    } else {});

    extraKnownMarketplaces = if isWork && workMarketplaceName != "" then {
      "${workMarketplaceName}" = {
        source = {
          source = "git";
          url = "git@github-work:${workMarketplaceRepo}.git";
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
    mcpServers = {
      nixos = {
        command = "${inputs.mcp-nixos.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/mcp-nixos";
      };
    };
    hooks = geminiHooks;
  };

  # List of extensions to ensure are installed
  geminiExtensions = [
    "https://github.com/samber/cc-skills-golang"
    "https://github.com/obra/superpowers"
    "https://github.com/mvanhorn/last30days-skill"
    "https://github.com/gemini-cli-extensions/security"
    "https://github.com/gemini-cli-extensions/code-review"
  ];
in
{
  home.file.".claude/settings.json".text = builtins.toJSON claudeSettings;
  home.file.".gemini/settings.json".text = builtins.toJSON geminiSettings;

  home.packages = [
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.gemini-cli
      inputs.mcp-nixos.packages.${pkgs.stdenv.hostPlatform.system}.default
      pkgs.python3 # Required for some extensions like last30days-skill
  ];

  # Automate extension installation on activation
  home.activation.installGeminiExtensions = lib.hm.dag.entryAfter ["writeBoundary"] ''
    $DRY_RUN_CMD ${inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.gemini-cli}/bin/gemini extensions list > /dev/null 2>&1 || true
    ${builtins.concatStringsSep "\n" (map (ext: ''
      echo "Ensuring Gemini extension is installed: ${ext}"
      $DRY_RUN_CMD ${inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.gemini-cli}/bin/gemini extensions install "${ext}" --consent --skip-settings || true
    '') geminiExtensions)}
  '';
}

