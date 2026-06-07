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
            command = "agent-state --agent ${agent} --state needs-input &";
          }
        ];
      }
    ];
    Stop = [
      {
        hooks = [
          {
            type = "command";
            command = "agent-state --agent ${agent} --state done &";
          }
        ];
      }
    ];
    PreToolUse = [
      {
        hooks = [
          {
            type = "command";
            command = "agent-state --agent ${agent} --state running &";
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
            command = "agent-state --agent gemini --state needs-input &";
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
            command = "agent-state --agent gemini --state running &";
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
            command = "agent-state --agent gemini --state running &";
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
            command = "agent-state --agent gemini --state done &";
          }
        ];
      }
    ];
  };

  antigravityHooks = {
    PreToolUse = [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            command = "agent-state --agent antigravity --state running &";
          }
        ];
      }
    ];
    PostToolUse = [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            command = "agent-state --agent antigravity --state done &";
          }
        ];
      }
    ];
    PreInvocation = [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            command = "agent-state --agent antigravity --state running &";
          }
        ];
      }
    ];
    PostInvocation = [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            command = "agent-state --agent antigravity --state done &";
          }
        ];
      }
    ];
    Stop = [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            command = "agent-state --agent antigravity --state done &";
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

  antigravitySettings = {
    colorScheme = "dark";
    enableTelemetry = false;
    model = "Gemini 3.5 Flash (Medium)";
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
    hooks = antigravityHooks;
  };

  opencodeSettings = {
    model = "opencode-go/deepseek-v4-pro";
    small_model = "opencode-go/deepseek-v4-flash";
    plugin = [ "./plugins/agent-state.ts" ];

    mcp = {
      nixos = {
        type = "local";
        command = [
          "${inputs.mcp-nixos.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/mcp-nixos"
        ];
      };
    };

    permission = {
      read = {
        ".env" = "deny";
        ".env.*" = "deny";
        "secrets/**" = "deny";
        "~/.aws/**" = "deny";
        "~/.zshrc" = "deny";
        "~/.bashrc" = "deny";
      };
      bash = {
        "npm *" = "deny";
        "npx *" = "deny";
        "*" = "ask";
      };
      edit = "ask";
    };
  };

  # List of { url, dir } pairs — dir is the actual directory name under ~/.gemini/extensions/
  geminiExtensions = [
    { url = "https://github.com/samber/cc-skills-golang";           dir = "cc-skills-golang"; }
    { url = "https://github.com/obra/superpowers";                  dir = "superpowers"; }
    { url = "https://github.com/gemini-cli-extensions/security";    dir = "gemini-cli-security"; }
    { url = "https://github.com/gemini-cli-extensions/code-review"; dir = "code-review"; }
  ];

  gemini = "${inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.gemini-cli}/bin/gemini";
  antigravity = "${inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.antigravity-cli}/bin/antigravity";
in
{
  home.file.".claude/settings.json".text = builtins.toJSON claudeSettings;
  home.file.".gemini/settings.json".text = builtins.toJSON geminiSettings;
  home.file.".config/opencode/opencode.json".text = builtins.toJSON opencodeSettings;
  home.file.".config/opencode/plugins/agent-state.ts".text = ''
    import type { Plugin } from "@opencode-ai/plugin";

    const AgentStatePlugin: Plugin = async ({ $ }) => {
      const notify = (state: string) => {
        $`agent-state --agent opencode --state ''${state}`;
      };

      return {
        "tool.execute.before": () => notify("running"),
        "tool.execute.after": () => notify("done"),
        event: ({ event }) => {
          if (event.type === "session.idle") {
            notify("done");
          }
          if (event.type === "error" || event.type === "notification") {
            notify("needs-input");
          }
        },
        stop: () => notify("done"),
      };
    };

    export default AgentStatePlugin;
  '';

  home.packages = [
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.gemini-cli
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.antigravity-cli
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode
      inputs.mcp-nixos.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  # Automate extension installation on activation
  home.activation.installGeminiExtensions = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # Prepend git but keep /usr/bin at the END so nix tools take priority
    export PATH="${pkgs.git}/bin:$PATH:/usr/bin"
    # Use system SSH so ~/.ssh/config macOS options (UseKeychain) are supported
    export GIT_SSH_COMMAND="/usr/bin/ssh"

    # 1. Antigravity Writable Settings Setup
    # We don't use home.file here because antigravity needs to write to its settings
    # but we still want them managed/reproducible by Nix.
    AGY_DIR="$HOME/.gemini/antigravity-cli"
    AGY_SETTINGS="$AGY_DIR/settings.json"
    mkdir -p "$AGY_DIR"
    if [ -L "$AGY_SETTINGS" ]; then rm "$AGY_SETTINGS"; fi

    # Write managed settings
    cat > "$AGY_SETTINGS" <<EOF
${builtins.toJSON antigravitySettings}
EOF
    chmod 644 "$AGY_SETTINGS"

    # 2. Gemini Extension Installation
    # Uninstall broken last30days-skill if still present on disk
    if [ -d "${config.home.homeDirectory}/.gemini/extensions/last30days-skill" ]; then
      echo "Removing last30days-skill extension..."
      ${gemini} extensions uninstall last30days-skill 2>/dev/null || \
        rm -rf "${config.home.homeDirectory}/.gemini/extensions/last30days-skill"
    fi

    # Install extensions for Gemini if not already present
    ${builtins.concatStringsSep "\n" (map (ext: ''
      if [ -d "$HOME/.gemini/extensions/${ext.dir}" ]; then
        echo "Gemini extension already installed: ${ext.dir}"
      else
        echo "Installing Gemini extension: ${ext.url}"
        $DRY_RUN_CMD ${gemini} extensions install "${ext.url}" --consent --skip-settings || true
      fi
    '') geminiExtensions)}

    # 3. Antigravity Plugin Installation
    AGY_PLUGINS_DIR="$HOME/.gemini/config/plugins"
    # Import plugins from gemini if none exist yet
    if [ ! -d "$AGY_PLUGINS_DIR" ] || [ -z "$(ls -A "$AGY_PLUGINS_DIR" 2>/dev/null)" ]; then
      echo "Importing plugins from gemini to antigravity..."
      $DRY_RUN_CMD ${antigravity} plugin import gemini --consent || true
    fi

    # Ensure all required extensions are installed in antigravity
    ${builtins.concatStringsSep "\n" (map (ext: ''
      if [ -d "$AGY_PLUGINS_DIR/${ext.dir}" ]; then
        echo "Antigravity plugin already installed: ${ext.dir}"
      else
        echo "Installing Antigravity plugin: ${ext.url}"
        $DRY_RUN_CMD ${antigravity} plugin install "${ext.url}" --consent --skip-settings || true
      fi
    '') geminiExtensions)}
  '';
}

