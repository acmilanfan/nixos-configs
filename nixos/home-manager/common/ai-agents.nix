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
    model = "opus";
    # Per-model effort, as written by `/effort` (keyed by full model id).
    modelSettings = {
      "claude-opus-5-5".effortLevel = "high";
      "claude-sonnet-5-5".effortLevel = "high";
      "claude-sonnet-5".effortLevel = "high";
    };
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

  claudeSettingsJson = builtins.toJSON claudeSettings;

  githubToken = (secrets.github or { }).token or "";

  antigravitySettings = {
    colorScheme = "tokyo night";
    editorMode = "vim";
    model = "Gemini 3.8 Flash (High)";
    notifications = true;
    showFeedbackSurvey = false;
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
    trustedWorkspaces = [
      "${config.home.homeDirectory}/configs/nixos-configs"
    ] ++ config.ai-agents.extraTrustedWorkspaces;
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
  # opencode config/plugins now live in ./opencode.nix.

  # Claude Code needs to write to its own settings.json at runtime (e.g. `/effort`,
  # `/model`), so it can't be a symlink into the read-only Nix store like a plain
  # home.file would create. We write a real, writable file instead (same trick as
  # the Antigravity settings below) and, before overwriting it on each activation,
  # diff the live file against the Nix-managed content so any runtime change that
  # should be made permanent gets surfaced instead of silently discarded.
  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    CLAUDE_DIR="$HOME/.claude"
    CLAUDE_SETTINGS="$CLAUDE_DIR/settings.json"
    mkdir -p "$CLAUDE_DIR"

    NEW_SETTINGS=$(cat <<'EOF'
${claudeSettingsJson}
EOF
    )

    if [ -L "$CLAUDE_SETTINGS" ]; then
      # Leftover symlink from the old home.file-managed version.
      rm "$CLAUDE_SETTINGS"
    elif [ -f "$CLAUDE_SETTINGS" ]; then
      OLD_SETTINGS=$(cat "$CLAUDE_SETTINGS")
      OLD_NORM=$(printf '%s' "$OLD_SETTINGS" | ${pkgs.jq}/bin/jq -S .)
      NEW_NORM=$(printf '%s' "$NEW_SETTINGS" | ${pkgs.jq}/bin/jq -S .)
      if [ "$OLD_NORM" != "$NEW_NORM" ]; then
        echo ""
        echo "==> ~/.claude/settings.json has drifted from the Nix-managed config (nixos/home-manager/common/ai-agents.nix)."
        echo "    Diff (live vs. nix-managed), about to be overwritten by the nix-managed version:"
        diff <(printf '%s\n' "$OLD_NORM") <(printf '%s\n' "$NEW_NORM") || true
        BACKUP="$CLAUDE_DIR/settings.json.drift.$(date +%s).json"
        printf '%s' "$OLD_SETTINGS" > "$BACKUP"
        echo "    Live version backed up to: $BACKUP"
        echo "    If any of these (e.g. an effort-level or model change) should persist,"
        echo "    add them to claudeSettings in nixos/home-manager/common/ai-agents.nix."
        echo ""
      fi
      # Keep only the 5 newest drift backups.
      ls -1t "$CLAUDE_DIR"/settings.json.drift.*.json 2>/dev/null | tail -n +6 | while read -r f; do rm -f "$f"; done || true
    fi

    printf '%s' "$NEW_SETTINGS" > "$CLAUDE_SETTINGS"
    chmod 644 "$CLAUDE_SETTINGS"
  '';

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
    # but we still want them managed/reproducible by Nix. Diff any live drift
    # against the Nix-managed content before overwriting (same as Claude
    # Code's settings.json activation) so a runtime change worth keeping gets
    # surfaced instead of silently discarded.
    AGY_DIR="$HOME/.gemini/antigravity-cli"
    AGY_SETTINGS="$AGY_DIR/settings.json"
    mkdir -p "$AGY_DIR"

    NEW_AGY_SETTINGS=$(cat <<'EOF'
${builtins.toJSON antigravitySettings}
EOF
    )

    if [ -L "$AGY_SETTINGS" ]; then
      rm "$AGY_SETTINGS"
    elif [ -f "$AGY_SETTINGS" ]; then
      OLD_AGY_SETTINGS=$(cat "$AGY_SETTINGS")
      OLD_AGY_NORM=$(printf '%s' "$OLD_AGY_SETTINGS" | ${pkgs.jq}/bin/jq -S .)
      NEW_AGY_NORM=$(printf '%s' "$NEW_AGY_SETTINGS" | ${pkgs.jq}/bin/jq -S .)
      if [ "$OLD_AGY_NORM" != "$NEW_AGY_NORM" ]; then
        echo ""
        echo "==> ~/.gemini/antigravity-cli/settings.json has drifted from the Nix-managed config (nixos/home-manager/common/ai-agents.nix)."
        echo "    Diff (live vs. nix-managed), about to be overwritten by the nix-managed version:"
        diff <(printf '%s\n' "$OLD_AGY_NORM") <(printf '%s\n' "$NEW_AGY_NORM") || true
        AGY_BACKUP="$AGY_DIR/settings.json.drift.$(date +%s).json"
        printf '%s' "$OLD_AGY_SETTINGS" > "$AGY_BACKUP"
        echo "    Live version backed up to: $AGY_BACKUP"
        echo "    If any of these should persist, add them to antigravitySettings in"
        echo "    nixos/home-manager/common/ai-agents.nix."
        echo ""
      fi
      ls -1t "$AGY_DIR"/settings.json.drift.*.json 2>/dev/null | tail -n +6 | while read -r f; do rm -f "$f"; done || true
    fi

    printf '%s' "$NEW_AGY_SETTINGS" > "$AGY_SETTINGS"
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

