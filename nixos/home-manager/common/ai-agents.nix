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
            # Claude Code fires Notification for both real permission prompts and the
            # routine "waiting for your input" idle nudge (notificationType:"idle_prompt").
            # Only the former should flip the sketchybar/Hammerspoon indicator red.
            command = ''
              input=$(cat)
              type=$(printf '%s' "$input" | ${pkgs.jq}/bin/jq -r '.notificationType // empty' 2>/dev/null)
              if [ "$type" != "idle_prompt" ]; then
                agent-state --agent ${agent} --state needs-input &
              fi
            '';
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
    SessionEnd = [
      {
        hooks = [
          {
            type = "command";
            command = "agent-state --agent ${agent} --state off &";
          }
        ];
      }
    ];
  };

  antigravityHooks = {
    Notification = [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            command = ''
              input=$(cat)
              type=$(printf '%s' "$input" | ${pkgs.jq}/bin/jq -r '.notificationType // empty' 2>/dev/null)
              if [ "$type" != "idle_prompt" ]; then
                agent-state --agent antigravity --state needs-input &
              fi
            '';
          }
        ];
      }
    ];
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
    SessionEnd = [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            command = "agent-state --agent antigravity --state off &";
          }
        ];
      }
    ];
  };

  claudeSettings = {
    # apiKeyHelper = "echo $ANTHROPIC_API_KEY";
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
    model = "opusplan[1m]";
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

  githubToken = (secrets.github or { }).token or "";

  antigravitySettings = {
    colorScheme = "dark";
    enableTelemetry = false;
    model = "Gemini 3.7 Flash (High)";
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
        command = "${pkgs.mcp-nixos}/bin/mcp-nixos";
      };
      github = {
        serverUrl = "https://api.githubcopilot.com/mcp/";
      } // (if githubToken != "" then {
        headers = {
          Authorization = "Bearer ${githubToken}";
        };
      } else {});
      context7 = {
        serverUrl = "https://mcp.context7.com/mcp";
      };
    };
    hooks = antigravityHooks;
  };

  # List of { url, dir } pairs — dir is the actual directory name under ~/.gemini/extensions/
  geminiExtensions = [
    { url = "https://github.com/samber/cc-skills-golang";           dir = "cc-skills-golang"; }
    { url = "https://github.com/obra/superpowers";                  dir = "superpowers"; }
    { url = "https://github.com/gemini-cli-extensions/security";    dir = "gemini-cli-security"; }
    { url = "https://github.com/gemini-cli-extensions/code-review"; dir = "code-review"; }
  ];

  antigravity = "${inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.antigravity-cli}/bin/antigravity";
in
{
  home.file.".claude/settings.json".text = builtins.toJSON claudeSettings;
  # opencode config/plugins now live in ./opencode.nix.

  home.packages = [
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.antigravity-cli
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode
      pkgs.mcp-nixos
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

    # 2. Antigravity Plugin Installation
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

