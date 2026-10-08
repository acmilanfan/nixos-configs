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
    "agent-state" = {
      PreInvocation = [
        {
          type = "command";
          command = ''
            export PATH="$PATH:/bin:/usr/bin:/usr/sbin:/sbin"
            ${startRemoteControl}
            agent-state --agent antigravity --state running & printf '{}'
          '';
        }
      ];
      PreToolUse = [
        {
          matcher = "*";
          hooks = [
            {
              type = "command";
              command = ''
                input=$(cat)
                tool=$(printf '%s' "$input" | ${pkgs.jq}/bin/jq -r '.toolCall.name // empty' 2>/dev/null)
                case "$tool" in
                  ask_question|run_command|write_to_file|replace_file_content|call_mcp_tool)
                    agent-state --agent antigravity --state needs-input &
                    ;;
                  *)
                    agent-state --agent antigravity --state running &
                    ;;
                esac
                printf '{"decision":"allow"}'
              '';
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
              command = "agent-state --agent antigravity --state running & printf '{}'";
            }
          ];
        }
      ];
      Stop = [
        {
          type = "command";
          command = ''
            input=$(cat)
            transcript=$(printf '%s' "$input" | ${pkgs.jq}/bin/jq -r '.transcriptPath // empty' 2>/dev/null)
            is_question=0
            if [ -n "$transcript" ] && [ -f "$transcript" ]; then
              rev_cmd=$(command -v tac 2>/dev/null || echo "tail -r")
              last_msg=$($rev_cmd "$transcript" 2>/dev/null | ${pkgs.jq}/bin/jq -r 'select(.type == "PLANNER_RESPONSE" and (.content | length > 0)) | .content' 2>/dev/null | head -n 1)
              if printf '%s' "$last_msg" | tail -n 5 | grep -q '\?'; then
                is_question=1
              fi
            fi
            if [ "$is_question" -eq 1 ]; then
              agent-state --agent antigravity --state needs-input &
            else
              agent-state --agent antigravity --state done &
            fi
            printf '{}'
          '';
        }
      ];
    };
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

  # GitHub MCP token: spliced into Antigravity's settings.json at activation
  # from the sops secret (see installGeminiExtensions), never via /nix/store.
  githubTokenFile = lib.optionalString (config.sops.secrets ? "github/token")
    config.sops.secrets."github/token".path;

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
      };
      context7 = {
        serverUrl = "https://mcp.context7.com/mcp";
      };
    };
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

  rawAgy = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.antigravity-cli;

  # Starts the agy remote-control daemon if it isn't running. Opt-in per host
  # (ai-agents.antigravity.remoteControl); empty otherwise. Shared by the
  # wrappers below and the PreInvocation hook.
  startRemoteControl = lib.optionalString config.ai-agents.antigravity.remoteControl ''
    if [ "''${1:-}" != "remote-control" ] && ! pgrep -f "remote-control.*serve" >/dev/null 2>&1; then
      HOST_NAME=$(/bin/hostname -s 2>/dev/null || hostname -s 2>/dev/null || echo "antigravity")
      nohup "${rawAgy}/bin/agy" remote-control start --name "$HOST_NAME" >/dev/null 2>&1 &
    fi
  '';

  mkAgyWrapper = name: pkgs.writeShellScriptBin name ''
    export PATH="$PATH:/bin:/usr/bin:/usr/sbin:/sbin"
    ${startRemoteControl}
    exec "${rawAgy}/bin/agy" "$@"
  '';

  antigravityWrapped = pkgs.symlinkJoin {
    name = "antigravity-cli-wrapped";
    paths = [
      (mkAgyWrapper "agy")
      (mkAgyWrapper "antigravity")
    ];
  };

  antigravity = "${rawAgy}/bin/agy";
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
      antigravityWrapped
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode
      pkgs.mcp-nixos
  ];

  # Automate extension installation on activation
  # After sops-nix so the GitHub token can be spliced into settings.json.
  home.activation.installGeminiExtensions = lib.hm.dag.entryAfter ["writeBoundary" "sops-nix"] (''
    # Prepend git but keep system bins at the END so launchctl/hostname and nix tools are available
    export PATH="${pkgs.git}/bin:$PATH:/usr/bin:/bin:/usr/sbin:/sbin"
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

    # GitHub MCP auth header from the sops secret. sops-nix's launchd agent
    # decrypts asynchronously, so give a fresh decryption a few seconds.
    GITHUB_TOKEN_FILE="${githubTokenFile}"
    if [ -n "$GITHUB_TOKEN_FILE" ]; then
      for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$GITHUB_TOKEN_FILE" ] && break; sleep 0.5; done
      if [ -s "$GITHUB_TOKEN_FILE" ]; then
        NEW_AGY_SETTINGS=$(printf '%s' "$NEW_AGY_SETTINGS" | ${pkgs.jq}/bin/jq -c --rawfile t "$GITHUB_TOKEN_FILE" \
          '.mcpServers.github.headers.Authorization = "Bearer " + ($t | rtrimstr("\n"))')
      fi
    fi

    if [ -L "$AGY_SETTINGS" ]; then
      rm "$AGY_SETTINGS"
    elif [ -f "$AGY_SETTINGS" ]; then
      OLD_AGY_SETTINGS=$(cat "$AGY_SETTINGS")
      # The auth header is left out of the comparison so the drift diff never
      # prints the token (and a rotated token isn't reported as drift).
      OLD_AGY_NORM=$(printf '%s' "$OLD_AGY_SETTINGS" | ${pkgs.jq}/bin/jq -S 'del(.mcpServers.github.headers)')
      NEW_AGY_NORM=$(printf '%s' "$NEW_AGY_SETTINGS" | ${pkgs.jq}/bin/jq -S 'del(.mcpServers.github.headers)')
      if [ "$OLD_AGY_NORM" != "$NEW_AGY_NORM" ]; then
        echo ""
        echo "==> ~/.gemini/antigravity-cli/settings.json has drifted from the Nix-managed config (nixos/home-manager/common/ai-agents.nix)."
        echo "    Diff (live vs. nix-managed), about to be overwritten by the nix-managed version:"
        diff <(printf '%s\n' "$OLD_AGY_NORM") <(printf '%s\n' "$NEW_AGY_NORM") || true
        AGY_BACKUP="$AGY_DIR/settings.json.drift.$(date +%s).json"
        (umask 077; printf '%s' "$OLD_AGY_SETTINGS" > "$AGY_BACKUP")
        echo "    Live version backed up to: $AGY_BACKUP"
        echo "    If any of these should persist, add them to antigravitySettings in"
        echo "    nixos/home-manager/common/ai-agents.nix."
        echo ""
      fi
      ls -1t "$AGY_DIR"/settings.json.drift.*.json 2>/dev/null | tail -n +6 | while read -r f; do rm -f "$f"; done || true
    fi

    printf '%s' "$NEW_AGY_SETTINGS" > "$AGY_SETTINGS"
    chmod 600 "$AGY_SETTINGS"

    # 2. Antigravity Global Hooks Setup (~/.gemini/config/hooks.json)
    AGY_CONFIG_DIR="$HOME/.gemini/config"
    AGY_HOOKS="$AGY_CONFIG_DIR/hooks.json"
    mkdir -p "$AGY_CONFIG_DIR"

    NEW_AGY_HOOKS=$(cat <<'EOF'
${builtins.toJSON antigravityHooks}
EOF
    )

    if [ -L "$AGY_HOOKS" ]; then
      rm "$AGY_HOOKS"
    elif [ -f "$AGY_HOOKS" ]; then
      OLD_AGY_HOOKS=$(cat "$AGY_HOOKS")
      OLD_HOOKS_NORM=$(printf '%s' "$OLD_AGY_HOOKS" | ${pkgs.jq}/bin/jq -S .)
      NEW_HOOKS_NORM=$(printf '%s' "$NEW_AGY_HOOKS" | ${pkgs.jq}/bin/jq -S .)
      if [ "$OLD_HOOKS_NORM" != "$NEW_HOOKS_NORM" ]; then
        echo ""
        echo "==> ~/.gemini/config/hooks.json has drifted from the Nix-managed config (nixos/home-manager/common/ai-agents.nix)."
        echo "    Diff (live vs. nix-managed), about to be overwritten by the nix-managed version:"
        diff <(printf '%s\n' "$OLD_HOOKS_NORM") <(printf '%s\n' "$NEW_HOOKS_NORM") || true
        HOOKS_BACKUP="$AGY_CONFIG_DIR/hooks.json.drift.$(date +%s).json"
        printf '%s' "$OLD_AGY_HOOKS" > "$HOOKS_BACKUP"
        echo "    Live version backed up to: $HOOKS_BACKUP"
        echo "    If any of these should persist, add them to antigravityHooks in"
        echo "    nixos/home-manager/common/ai-agents.nix."
        echo ""
      fi
      ls -1t "$AGY_CONFIG_DIR"/hooks.json.drift.*.json 2>/dev/null | tail -n +6 | while read -r f; do rm -f "$f"; done || true
    fi

    printf '%s' "$NEW_AGY_HOOKS" > "$AGY_HOOKS"
    chmod 644 "$AGY_HOOKS"

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

  '' + lib.optionalString config.ai-agents.antigravity.remoteControl ''

    # 4. Antigravity Remote Control Daemon Setup (opt-in per host)
    # Ensure the remote-control daemon is registered with this host's machine name
    HOST_NAME=$(/bin/hostname -s 2>/dev/null || hostname -s 2>/dev/null || echo "antigravity")
    $DRY_RUN_CMD ${rawAgy}/bin/agy remote-control start --name "$HOST_NAME" || true
  '');
}

