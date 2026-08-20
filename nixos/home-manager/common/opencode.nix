{ config, secrets, pkgs, unstable, inputs, lib, ... }:
let
  isWork = config.home.username == "andreishumailov";

  # Reuses the same private marketplace secret already used for Claude Code
  # (ai-agents.nix) — the repo holds skills/agents/commands for coding-java,
  # scorecard, global-skills, jdtls-java, check-setup.
  workMarketplaceRepo = secrets.claude.workMarketplaceRepo or "";

  # -------------------------------------------------------------------------
  # Providers
  #
  # All company URLs/keys are referenced via {env:VAR} — opencode substitutes
  # these from the shell environment at runtime, so no literal company value
  # ever lands in /nix/store or the committed repo. The env vars themselves
  # are set from `secrets.*` in neovim.nix.
  # -------------------------------------------------------------------------

  remoteProviders = {
    anthropic = {
      options = {
        # baseURL = "{env:ANTHROPIC_BASE_URL}";
        # apiKey = "{env:ANTHROPIC_API_KEY}";
      };
      models = {
        "claude-opus-4-8" = {
          name = "Claude Opus";
        };
        "claude-sonnet-5" = {
          name = "Claude Sonnet";
        };
        "claude-haiku-4-5-20251001" = {
          name = "Claude Haiku";
        };
      };
    };

    openai = {
      npm = "@ai-sdk/openai-compatible";
      name = "OpenAI (internal proxy)";
      options = {
        baseURL = "{env:AI_PROXY_OPENAI}";
        apiKey = "{env:AI_PROXY_API_KEY}";
      };
      models = {
        "gpt-5.6-sol" = {
          name = "GPT-5.6 Sol";
        };
        "gpt-5.6-terra" = {
          name = "GPT-5.6 Terra";
        };
        "gpt-5.6-luna" = {
          name = "GPT-5.6 Luna";
        };
      };
    };

    # Self-hosted Qwen 3.6, exposed via the internal AI proxy. Shape mirrors
    # this org's own self-hosted-model proxy integration (kept generic here —
    # no internal repo/PR references or hostnames in the committed config).
    "self-hosted" = {
      npm = "@ai-sdk/openai-compatible";
      name = "Self-hosted (internal proxy)";
      options = {
        baseURL = "{env:SELF_HOSTED_BASE_URL}";
        apiKey = "{env:SELF_HOSTED_API_KEY}";
      };
      models = {
        "Qwen/Qwen3.6-35B-A3B-FP8" = {
          name = "Qwen3.6 35B A3B FP8";
          limit = {
            context = 128000;
            output = 8192;
          };
        };
      };
    };
  };

  # Local, on-demand OpenAI-compatible servers (both machines). Start with
  # `serve-qwen` / `serve-gemma` (below); the provider just points at the
  # local port, so it's a no-op entry until a server is actually running.
  localProviders = {
    ollama = {
      npm = "@ai-sdk/openai-compatible";
      name = "Ollama (local)";
      options = {
        baseURL = "http://127.0.0.1:11434/v1";
        apiKey = "local";
      };
      models = {
        "gemma4:26b-mlx" = {
          name = "Gemma 4 26B MoE MLX (Ollama)";
        };
        "gemma4:12b-mlx" = {
          name = "Gemma 4 12B MLX (Ollama)";
        };
        "gemma4:31b-mlx" = {
          name = "Gemma 4 31B MLX (Ollama)";
        };
        "qwen3.6:27b-mlx" = {
          name = "Qwen 3.6 27B MLX (Ollama)";
        };
        "qwen3.6:35b-mlx" = {
          name = "Qwen 3.6 35B MoE MLX (Ollama)";
        };
        "muse-glimmer:30b-mlx" = {
          name = "Muse Glimmer 30B MLX (Ollama)";
        };
        "hf.co/unsloth/Llama-3_3-Nemotron-Super-49B-v1_5-GGUF:Q4_K_M" = {
          name = "Nemotron Super 49B (Ollama)";
        };
      };
    };

    mlx = {
      npm = "@ai-sdk/openai-compatible";
      name = "MLX 31B (local)";
      options = {
        baseURL = "http://127.0.0.1:8080/v1";
        apiKey = "local";
      };
      models = {
        "mlx-community/gemma-4-31b-it-6bit" = {
          name = "Gemma 4 31B 6-bit (MLX, local)";
        };
      };
    };

    mlxSmall = {
      npm = "@ai-sdk/openai-compatible";
      name = "MLX 12B (local, vision)";
      options = {
        baseURL = "http://127.0.0.1:8082/v1";
        apiKey = "local";
      };
      models = {
        "mlx-community/gemma-4-12B-it-6bit" = {
          name = "Gemma 4 12B 6-bit (MLX, local, vision)";
          attachment = true;
          modalities.input = ["text" "image"];
        };
      };
    };

    mtplx = {
      npm = "@ai-sdk/openai-compatible";
      name = "MTPLX Qwen (local)";
      options = {
        baseURL = "http://127.0.0.1:8081/v1";
        apiKey = "local";
      };
      models = {
        "mtplx-qwen38-27b-optimized-speed" = {
          name = "Qwen3.8 27B (MTPLX Optimized Speed, local)";
        };
      };
    };

    # Preferred local engine on mac-home (Homebrew CLI, not in nixpkgs). Serves
    # on :8083, TurboQuant q4 KV, MTP off — see serve-omlx for the tradeoff.
    omlx = {
      npm = "@ai-sdk/openai-compatible";
      name = "oMLX (local, TurboQuant)";
      options = {
        baseURL = "http://127.0.0.1:8083/v1";
        apiKey = "local";
      };
      models = {
        "Qwen3.8-27B-oQ4e-mtp" = {
          name = "Qwen3.8 27B oQ4e-MTP (oMLX, local)";
        };
        "Qwen3.6-35B-A3B-oQ4e-mtp" = {
          name = "Qwen3.6 35B A3B oQ4e (oMLX, local)";
        };
        "gemma-4-26B-A4B-it-oQ4e-mtp" = {
          name = "Gemma 4 26B A4B oQ4e (oMLX, local)";
        };
        "gemma-4-31B-it-oQ4e-mtp" = {
          name = "Gemma 4 31B oQ4e (oMLX, local)";
        };
        "gemma-4-12B-it-qat-oQ4e-mtp" = {
          name = "Gemma 4 12B QAT oQ4e (oMLX, local)";
        };
      };
    };
  };

  opencodeSettings = {
    "$schema" = "https://opencode.ai/config.json";

    # model = if isWork then "anthropic/claude-sonnet-5" else "opencode-go/deepseek-v4-pro";
    # DeepSeek's Aug 16 2026 pricing cut moved it to a much lower Go usage
    # tier (peak/off-peak, far fewer requests/month); mimo-v2.5 kept the
    # higher tier and is now the better high-volume default. Switch to
    # opencode-go/qwen3.7-plus manually for harder reasoning/refactor tasks.
    model = if isWork then "self-hosted/Qwen/Qwen3.6-35B-A3B-FP8" else "opencode-go/mimo-v2.5";
    small_model = if isWork then "self-hosted/Qwen/Qwen3.6-35B-A3B-FP8" else "opencode-go/mimo-v2.5";

    provider = localProviders // (if isWork then remoteProviders else { });

    # Work: point at the existing hand-written ~/Work/CLAUDE.md (kept outside
    # the repo, never committed). Home: a small generic AGENTS.md we manage.
    instructions = if isWork then [ "/Users/andreishumailov/Work/CLAUDE.md" ] else [ "AGENTS.md" ];

    mcp = {
      nixos = {
        type = "local";
        command = [ "${pkgs.mcp-nixos}/bin/mcp-nixos" ];
      };
      github = {
        type = "remote";
        url = "https://api.githubcopilot.com/mcp/";
        headers = {
          Authorization = "Bearer {env:GITHUB_PERSONAL_ACCESS_TOKEN}";
        };
      };
      context7 = {
        type = "remote";
        url = "https://mcp.context7.com/mcp";
      };
    } // (if isWork then {
      "core-developers-assistant-rag" = {
        type = "remote";
        url = "{env:RAG_MCP_URL}";
      };
      scorecard = {
        type = "remote";
        url = "{env:SCORECARD_MCP_URL}";
      };
      # Public host, but OAuth login is required on first use
      # (`opencode auth login` or in-session prompt) — see plan verification.
      # The old /v1/sse endpoint is deprecated after 30 June 2026; using the
      # streamable-HTTP /v1/mcp endpoint instead.
      atlassian = {
        type = "remote";
        url = "https://mcp.atlassian.com/v1/mcp";
      };
      sonarqube = {
        type = "local";
        command = [
          "docker"
          "run"
          "-i"
          "--rm"
          "--init"
          "--pull=always"
          "-e"
          "SONARQUBE_TOKEN"
          "-e"
          "SONARQUBE_URL"
          "mcp/sonarqube"
        ];
        environment = {
          SONARQUBE_TOKEN = "{env:SONAR_API_KEY}";
          SONARQUBE_URL = "{env:SONAR_URL}";
        };
      };
    } else { });

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

  # -------------------------------------------------------------------------
  # Local model runtimes — on-demand wrapper scripts (not always-on daemons,
  # to preserve RAM on a 48GB machine). Run `serve-qwen`/`serve-gemma`
  # manually (or wire a launchd agent later) before using the corresponding
  # opencode provider.
  # -------------------------------------------------------------------------

  # Built via uv2nix (nixos/common/pkgs/mtplx) — a real Nix-store package
  # pinned by uv.lock, not a runtime PyPI fetch. Darwin-only (see overlays.nix).
  serveQwen = pkgs.writeShellScriptBin "serve-qwen" ''
    set -euo pipefail

    # MTPLX uses MLX-format HF repos (official: huggingface.co/Youssofal).
    MODEL="''${QWEN_MLX:-Youssofal/Qwen3.8-27B-MTPLX-Optimized-Speed}"
    CACHE_DIR="$HOME/ai/models"

    echo "Starting MTPLX (Qwen 3.8 Optimized Speed) on :8081 ..."

    mkdir -p "$CACHE_DIR"

    # `--paged-kv-quantization q4` is TurboQuant-style KV cache (keys 8-bit,
    # values 4-bit), stretching the 27B model's context on 48 GB. NOTE: with MTP
    # on (observed 2.8.2) the quantised paged-KV variant is skipped in the
    # compiled-verify path, so the flag is only partially in effect — treat MTP
    # and cheap KV as mutually exclusive until measured otherwise.
    # mtplx's "session bank" prefix cache auto-sizes to half the post-model RAM
    # surplus (e.g. 14.1G) — a large standing reservation. Shrink it to trade
    # cache for context, or grow it for more sessions.
    export MTPLX_SESSION_BANK_MAX_BYTES="''${MTPLX_SESSION_BANK_MAX_BYTES:-}"
    export MTPLX_SESSION_BANK_PER_SESSION_BYTES="''${MTPLX_SESSION_BANK_PER_SESSION_BYTES:-}"
    [ -n "$MTPLX_SESSION_BANK_MAX_BYTES" ] || unset MTPLX_SESSION_BANK_MAX_BYTES
    [ -n "$MTPLX_SESSION_BANK_PER_SESSION_BYTES" ] || unset MTPLX_SESSION_BANK_PER_SESSION_BYTES

    ${unstable.mtplx}/bin/mtplx pull "$MODEL" --cache-dir "$CACHE_DIR"
    exec ${unstable.mtplx}/bin/mtplx quickstart \
      --model "$MODEL" \
      --cache-dir "$CACHE_DIR" \
      --host 127.0.0.1 \
      --port 8081 \
      --paged-kv-quantization q4 \
      --yes
  '';

  # oMLX (Homebrew CLI, not in nixpkgs): multi-model MLX server on :8083.
  # Serves the oQ4e MLX builds of the same models Ollama provides (qwen 3.6
  # 35B, gemma4 12B/26B/31B) plus the Qwen 3.8 27B. Models download on first
  # run into ~/ai/models/omlx/. Two 27B-class servers can't share 48 GB — run
  # this instead of serve-qwen, not alongside it.
  serveOmlx = pkgs.writeShellScriptBin "serve-omlx" ''
    set -euo pipefail

    export OMLX_MODEL_DIR="$HOME/ai/models/omlx"

    # oQ4e MLX builds of the same models Ollama serves (qwen 3.6 35B, gemma4
    # 12B/26B/31B) plus the existing Qwen 3.8 27B. First-party oQ4e from the
    # oMLX author (HF Jundot), except the 12B (no Jundot build; djrsystemservices
    # QAT oQ4e instead). Each is downloaded on first `serve-omlx` run if its
    # config.json is absent. OMLX_MODEL_REPO overrides with a single model;
    # OMLX_MODEL_ID overrides the settings.json ID (defaults to repo basename).
    DEFAULT_MODELS=(
      "Jundot/Qwen3.8-27B-oQ4e-mtp"
      "Jundot/Qwen3.6-35B-A3B-oQ4e-mtp"
      "Jundot/gemma-4-26B-A4B-it-oQ4e-mtp"
      "Jundot/gemma-4-31B-it-oQ4e-mtp"
      "djrsystemservices/gemma-4-12B-it-qat-oQ4e-mtp"
    )

    if [ -n "''${OMLX_MODEL_REPO:-}" ]; then
      MODELS=( "$OMLX_MODEL_REPO" )
    else
      MODELS=( "''${DEFAULT_MODELS[@]}" )
    fi

    OMLX_BIN="''${OMLX_BIN:-}"
    if [ -z "$OMLX_BIN" ]; then
      OMLX_BIN="$(command -v omlx 2>/dev/null || true)"
      [ -z "$OMLX_BIN" ] && OMLX_BIN="/opt/homebrew/opt/omlx/bin/omlx"
    fi

    mkdir -p "$OMLX_MODEL_DIR"

    for MODEL_REPO in "''${MODELS[@]}"; do
      NAME="''${MODEL_REPO##*/}"
      MODEL_ID="''${OMLX_MODEL_ID:-$NAME}"

      if [ ! -f "$OMLX_MODEL_DIR/$NAME/config.json" ]; then
        echo "oMLX: downloading $MODEL_REPO (one-time) ..."
        export PATH="${pkgs.uv}/bin:$PATH"
        uvx --from huggingface_hub hf download "$MODEL_REPO" --local-dir "$OMLX_MODEL_DIR/$NAME"
      fi

      # MTP and TurboQuant are set per model in ~/.omlx/model_settings.json
      # (read at startup). They don't stack on this arch: MTP-on suppresses KV
      # quantisation (~213 KB/token vs ~16 KB for q4), so a 72k prefill needed
      # 43.55 GB. Confirmed 2026-08-19 by A/B — with MTP off, TurboQuant engages
      # and 80k+ context works (~12.4 -> ~9 tok/s). MTP is OFF by default here;
      # flip per-run with OMLX_MTP=1 (speed) or OMLX_TURBOQUANT=0.
      ${pkgs.python3}/bin/python3 -c '
import json, os, sys
mid, mtp, tq, bits = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
path = os.path.expanduser("~/.omlx/model_settings.json")
data = {}
if os.path.exists(path):
    try:
        data = json.load(open(path))
    except Exception:
        pass
m = data.setdefault("models", {}).setdefault(mid, {})
m["mtp_enabled"] = mtp not in ("0", "false", "no")
m["turboquant_kv_enabled"] = tq not in ("0", "false", "no")
m["turboquant_kv_bits"] = int(bits)
json.dump(data, open(path, "w"), indent=2)
print("model_settings: %s mtp=%s turboquant=%s bits=%s"
      % (mid, m["mtp_enabled"], m["turboquant_kv_enabled"], m["turboquant_kv_bits"]))
' "$MODEL_ID" "''${OMLX_MTP:-0}" "''${OMLX_TURBOQUANT:-1}" "''${OMLX_TURBOQUANT_BITS:-4}"
    done

    # oMLX caps = fraction of min(this guard, Metal wired limit): soft 85%,
    # hard 95%. Raised 44 -> 46 so the Metal ceiling binds (prefill cap 42.7
    # GB). Note the ~240 KB/token figure in older comments was measured with MTP
    # on (TurboQuant suppressed); with MTP off KV is quantised and much cheaper.
    # Override to sweep: OMLX_MEMORY_GUARD_GB=46 serve-omlx.
    GUARD_GB="''${OMLX_MEMORY_GUARD_GB:-46}"

    echo "Starting oMLX on :8083, memory guard ''${GUARD_GB}GB ..."
    exec "$OMLX_BIN" serve \
      --model-dir "$OMLX_MODEL_DIR" \
      --host 127.0.0.1 \
      --port 8083 \
      --memory-guard-gb "$GUARD_GB"
  '';

  # Smaller Gemma 4 12B (~6.7 GB), can coexist with Qwen 27B on 48 GB.
  serveGemmaSmall = pkgs.writeShellScriptBin "serve-gemma-small" ''
    set -euo pipefail

    export PATH="${pkgs.uv}/bin:$PATH"
    export HF_HOME="$HOME/ai/models/huggingface"

    echo "Starting MLX (Gemma 4 12B vision) on :8082 ..."
    exec uvx --python 3.11 --from mlx-vlm mlx_vlm.server \
      --model "''${GEMMA_SMALL_MODEL:-mlx-community/gemma-4-12B-it-6bit}" \
      --port 8082 \
      --max-kv-size "$((4 * 1024 * 1024 * 1024))"
  '';

  # Ollama: runs the bundled llama.cpp server + pulls the model on first use.
  # Models are stored in ~/ai/models/ollama (set via OLLAMA_MODELS).
  serveOllama = pkgs.writeShellScriptBin "serve-ollama" ''
    set -euo pipefail

    export OLLAMA_MODELS="$HOME/ai/models/ollama"
    export OLLAMA_HOST="127.0.0.1:11434"

    # KV cache quantisation. Unlike oMLX/mtplx (where quantised KV collides with
    # MTP verify), ollama has no MTP so this actually applies. q8_0 halves KV vs
    # f16 with negligible quality loss; q4_0 quarters it with a modest loss that
    # shows more at long context. Keys are more sensitive than values, and ollama
    # only exposes a uniform setting, so q8_0 is the safer default. Requires
    # flash attention; whether it takes effect under ollama's MLX backend
    # (preview) is unverified — check actual memory use. TurboQuant is NOT
    # available here (the llama.cpp PR was closed unmerged).
    export OLLAMA_KV_CACHE_TYPE="''${OLLAMA_KV_CACHE_TYPE:-q8_0}"

    if ! ollama list &>/dev/null; then
      echo "Starting ollama serve..." >&2
      ollama serve &>/dev/null &
      sleep 2
    fi

    MODEL="''${OLLAMA_MODEL:-gemma4:26b-mlx}"
    EXTRA_MODELS="''${OLLAMA_EXTRA_MODELS:-gemma4:12b-mlx qwen3.6:27b-mlx hf.co/unsloth/Llama-3_3-Nemotron-Super-49B-v1_5-GGUF:Q4_K_M}"
    echo "Ollama: pulling ''${MODEL} (one-time) ..."
    ollama pull "$MODEL"

    if [ -n "$EXTRA_MODELS" ]; then
      echo "Ollama: pulling extra models: $EXTRA_MODELS"
      for m in $EXTRA_MODELS; do
        ollama pull "$m"
      done
    fi

    echo "Ollama ready on http://127.0.0.1:11434"
  '';

  # Quick shortcuts for common Ollama MLX models.
  # Usage: opencode-qwen "refactor this file"
  ocOllama = model: name: pkgs.writeShellScriptBin "oc-${name}" ''
    exec opencode run -m "ollama/${model}" "''${@}"
  '';
  ocQwen27b   = ocOllama "qwen3.6:27b-mlx"    "qwen27b";
  ocQwen35b   = ocOllama "qwen3.6:35b-mlx"    "qwen35b";
  ocGemma26b  = ocOllama "gemma4:26b-mlx"     "gemma26b";
  ocGemma31b  = ocOllama "gemma4:31b-mlx"     "gemma31b";
  ocNemotron  = ocOllama "hf.co/unsloth/Llama-3_3-Nemotron-Super-49B-v1_5-GGUF:Q4_K_M" "nemotron";

  # Puts both on-demand local model servers in one detached tmux session
  # (one window each) instead of tying up a foreground pane, and
  # switches/attaches to it. Re-running is a no-op if the session already
  # exists — same idempotency pattern as tmux-sessionizer.
  aiModels = pkgs.writeShellScriptBin "ai-models" ''
    set -euo pipefail
    SESSION=ai-models

    if ! ${pkgs.tmux}/bin/tmux has-session -t="$SESSION" 2>/dev/null; then
      ${pkgs.tmux}/bin/tmux new-session -ds "$SESSION" -n qwen "serve-qwen; exec $SHELL"
      ${pkgs.tmux}/bin/tmux new-window -t "$SESSION" -n gemma12b "serve-gemma-small; exec $SHELL"
      ${pkgs.tmux}/bin/tmux new-window -t "$SESSION" -n ollama "serve-ollama; exec $SHELL"
      ${pkgs.tmux}/bin/tmux new-window -t "$SESSION" -n omlx "serve-omlx; exec $SHELL"
    fi

    if [ -n "''${TMUX:-}" ]; then
      ${pkgs.tmux}/bin/tmux switch-client -t "$SESSION"
    else
      ${pkgs.tmux}/bin/tmux attach -t "$SESSION"
    fi
  '';

  # -------------------------------------------------------------------------
  # Claude agent -> opencode agent frontmatter converter (work only). Reads
  # Claude Code subagent .md files (name/description/model/tools/color/skills
  # frontmatter) and emits opencode's agent frontmatter (mode/model/tools),
  # keeping the system-prompt body verbatim.
  # -------------------------------------------------------------------------

  agentConverter = pkgs.writers.writePython3 "convert-claude-agent"
    {
      libraries = [ pkgs.python3Packages.pyyaml ];
      flakeIgnore = [ "E111" "E114" "E121" ];
    } ''
    import sys
    import yaml

    MODEL_MAP = {
        "opus": "anthropic/claude-opus-4-8",
        "sonnet": "anthropic/claude-sonnet-5",
        "haiku": "anthropic/claude-haiku-4-5-20251001",
    }

    # Claude tool name -> opencode tool name. Unrecognized tools are dropped
    # (with a warning) rather than guessed at.
    TOOL_MAP = {
        "Glob": "glob",
        "Grep": "grep",
        "LS": "list",
        "Read": "read",
        "Write": "write",
        "Edit": "edit",
        "WebFetch": "webfetch",
        "TodoWrite": "todowrite",
        "Bash": "bash",
        "KillShell": "bash",
        "BashOutput": "bash",
    }


    def parse_frontmatter(text):
        if not text.startswith("---\n"):
            raise ValueError("no frontmatter")
        end = text.index("\n---", 4)
        fm = yaml.safe_load(text[4:end])
        body = text[end + 4:].lstrip("\n")
        return fm, body


    def convert_tools(raw):
        if raw is None:
            return None
        if isinstance(raw, str):
            names = [t.strip() for t in raw.split(",") if t.strip()]
        elif isinstance(raw, list):
            names = raw
        else:
            return None
        tools = {}
        for name in names:
            mapped = TOOL_MAP.get(name)
            if mapped is None:
                msg = f"convert-claude-agent: skipping unmapped tool '{name}'"
                print(msg, file=sys.stderr)
                continue
            tools[mapped] = True
        return tools or None


    def convert_one(src, dst):
        with open(src) as f:
            text = f.read()

        fm, body = parse_frontmatter(text)

        out_fm = {
            "description": fm.get("description", ""),
            "mode": "subagent",
        }

        model = fm.get("model")
        if model and model != "inherit":
            out_fm["model"] = MODEL_MAP.get(model, model)

        tools = convert_tools(fm.get("tools"))
        if tools:
            out_fm["tools"] = tools

        with open(dst, "w") as f:
            f.write("---\n")
            f.write(yaml.safe_dump(out_fm, sort_keys=False))
            f.write("---\n\n")
            f.write(body)


    def plugin_name_for(src):
        # src is .../plugins/<plugin>/agents/<file>.md
        import os
        return os.path.basename(os.path.dirname(os.path.dirname(src)))


    def main():
        import os

        dest_dir = sys.argv[1]
        sources = sys.argv[2:]

        # Several plugins ship an agent with the same conventional basename
        # (e.g. every language plugin has its own rag-caller.md). The
        # destination is a single flat directory, so writing all of them
        # under their bare basename would let the alphabetically-last
        # plugin silently clobber the rest. Only basenames that actually
        # collide get a plugin-name prefix, so unambiguous agents (e.g.
        # troubleshooter-java.md) keep their plain name.
        by_basename = {}
        for src in sources:
            by_basename.setdefault(os.path.basename(src), []).append(src)

        for src in sources:
            base = os.path.basename(src)
            if len(by_basename[base]) > 1:
                dst_name = f"{plugin_name_for(src)}-{base}"
                print(
                    f"convert-claude-agent: '{base}' is shipped by "
                    f"{len(by_basename[base])} plugins; disambiguating as "
                    f"'{dst_name}'",
                    file=sys.stderr,
                )
            else:
                dst_name = base
            try:
                convert_one(src, os.path.join(dest_dir, dst_name))
            except Exception as e:
                print(
                    f"convert-claude-agent: failed to convert '{src}': {e}",
                    file=sys.stderr,
                )


    if __name__ == "__main__":
        main()
  '';

  workAssetsDir = "$HOME/.cache/opencode-work-assets";
  superpowersDir = "$HOME/.cache/opencode-superpowers";

  aiWorkspaceDirs = [ "projects" "docs" "instructions" "models" "artifacts" ];
in
{
  home.file.".config/opencode/opencode.json".text = builtins.toJSON opencodeSettings;

  home.file.".config/opencode/plugins/agent-state.ts".text = ''
    import type { Plugin } from "@opencode-ai/plugin";

    const AgentStatePlugin: Plugin = async ({ $ }) => {
      const notify = async (state: string) => {
        await $`agent-state --agent opencode --state ''${state}`;
      };

      return {
        "tool.execute.before": async () => { await notify("running"); },
        event: async ({ event }) => {
          if (event.type === "session.idle") {
            await notify("done");
          }
          if (event.type === "session.error") {
            await notify("needs-input");
          }
        },
      };
    };

    export default AgentStatePlugin;
  '';

  home.file.".config/opencode/AGENTS.md" = lib.mkIf (!isWork) {
    text = ''
      # opencode instructions

      Generic, machine-local guidance (no company content — this file is
      committed to nixos-configs).

      - Prefer existing skills (the `superpowers` plugin registers its own
        skills directory — use the `skill` tool to discover them) over
        ad-hoc approaches.
      - Local models (`mlx`, `llamacpp` providers) are on-demand: run
        `serve-gemma` / `serve-qwen` first, then select the provider.
      - Real project work happens in-place (project root, or a `wt-new`
        worktree sibling) — never stage it under `~/ai/projects/`.
      - Write scratch/debug output (logs, transcripts, one-off dumps) to
        `~/ai/artifacts/<project-name>/` instead of the repo working tree or
        `/tmp`, so it survives past the session. See `~/ai/instructions/README.md`
        for the full folder convention.
    '';
  };

  home.file.".local/share/ai-workspace-readme" = {
    text = ''
      ~/ai workspace layout:
        projects/     throwaway scratch clones only — a repo/tool you want an
                      agent to poke at that isn't real project work. Actual
                      projects and their features stay in ~/Work/IdeaProjects
                      (or ~/IdeaProjects) and wt-new worktree siblings; this
                      folder never competes with that.
        docs/         design docs, research notes, plans that outlive a
                      single repo/worktree (survives after a worktree is
                      wt-rm'd)
        instructions/ AGENTS.md / CLAUDE.md fragments to symlink into a
                      project root when you want to share guidance across
                      projects (human-managed, not auto-read by agents)
        models/       local GGUF (qwen) + MLX cache used by serve-qwen/serve-gemma
        artifacts/    scratch/debug output (logs, transcripts, error dumps)
                      per project — agents write here instead of discarding
                      it or littering the repo; kept out of git
    '';
  };

  # Note: agentConverter is a bare writers.writePython3 script (a file, not a
  # package with bin/), so it's invoked directly by path from the activation
  # script below rather than added to home.packages (buildEnv can't merge a
  # bare file at the top level).
  home.packages = [
    pkgs.uv
    aiModels
  ] ++ lib.optionals pkgs.stdenv.isDarwin [
    # serveQwen/serveGemma reference Darwin-only Nix-store packages
    # (unstable.mtplx, unstable.python312Packages.mlx-lm) — this file is
    # shared with Linux hosts, which must never force those derivations.
    serveQwen
    serveOmlx
    serveGemmaSmall
    serveOllama
    ocQwen27b
    ocQwen35b
    ocGemma26b
    ocGemma31b
    ocNemotron
  ];

  # Workspace + opencode asset directories always exist, reproducibly.
  home.activation.opencodeWorkspace = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p ${lib.concatStringsSep " " (map (d: "$HOME/ai/${d}") aiWorkspaceDirs)}
    mkdir -p "$HOME/.config/opencode/skills" "$HOME/.config/opencode/plugins"
    mkdir -p "$HOME/.config/opencode/agent" "$HOME/.config/opencode/command"
  '';

  # Generic (both machines): pull superpowers' skills + its native opencode
  # plugin straight from the public repo, the same way installGeminiExtensions
  # already does for Gemini — plain git clone/pull, no flake pinning needed
  # for content that's meant to stay current.
  home.activation.opencodeSuperpowers = lib.hm.dag.entryAfter [ "writeBoundary" "opencodeWorkspace" ] ''
    export PATH="${pkgs.git}/bin:$PATH:/usr/bin"

    if [ -d "${superpowersDir}/.git" ]; then
      $DRY_RUN_CMD git -C "${superpowersDir}" pull --ff-only || true
    else
      $DRY_RUN_CMD git clone --depth 1 https://github.com/obra/superpowers "${superpowersDir}" || true
    fi

    # Skills are intentionally NOT symlinked into ~/.config/opencode/skills/ —
    # the superpowers.js plugin below registers "${superpowersDir}/skills"
    # itself via opencode's config hook (config.skills.paths). Symlinking it
    # too would make opencode discover every superpowers skill twice (once
    # via directory scan, once via the plugin's own registration).
    if [ -d "${superpowersDir}/commands" ]; then
      ln -sfn "${superpowersDir}/commands" "$HOME/.config/opencode/command/superpowers"
    fi
    if [ -f "${superpowersDir}/.opencode/plugins/superpowers.js" ]; then
      ln -sfn "${superpowersDir}/.opencode/plugins/superpowers.js" "$HOME/.config/opencode/plugins/superpowers.js"
    fi
  '';

  # Work only: private marketplace clone + skills/commands symlinks + agent
  # frontmatter conversion. Nothing company-specific is committed — the repo
  # URL comes from the secrets submodule and conversion happens post-clone.
  home.activation.opencodeWorkAssets = lib.mkIf isWork (
    lib.hm.dag.entryAfter [ "writeBoundary" "opencodeWorkspace" ] ''
      export PATH="${pkgs.git}/bin:$PATH:/usr/bin"
      export GIT_SSH_COMMAND="/usr/bin/ssh"

      ${lib.optionalString (workMarketplaceRepo != "") ''
        if [ -d "${workAssetsDir}/.git" ]; then
          $DRY_RUN_CMD git -C "${workAssetsDir}" pull --ff-only || true
        else
          $DRY_RUN_CMD git clone "git@github-work:${workMarketplaceRepo}.git" "${workAssetsDir}" || true
        fi

        for plugin_dir in "${workAssetsDir}"/plugins/*/skills; do
          [ -d "$plugin_dir" ] || continue
          plugin_name=$(basename "$(dirname "$plugin_dir")")
          ln -sfn "$plugin_dir" "$HOME/.config/opencode/skills/$plugin_name"
        done

        for cmd_dir in "${workAssetsDir}"/plugins/*/commands; do
          [ -d "$cmd_dir" ] || continue
          plugin_name=$(basename "$(dirname "$cmd_dir")")
          ln -sfn "$cmd_dir" "$HOME/.config/opencode/command/$plugin_name"
        done

        # Regenerate from scratch each run: the converter decides, across the
        # full set of source agents, which basenames collide across plugins
        # and need a plugin-name prefix, so stale flat-named output from a
        # previous (colliding) run doesn't linger alongside the fix.
        rm -f "$HOME/.config/opencode/agent"/*.md
        agent_files=("${workAssetsDir}"/plugins/*/agents/*.md)
        if [ -e "''${agent_files[0]}" ]; then
          $DRY_RUN_CMD ${agentConverter} "$HOME/.config/opencode/agent" "''${agent_files[@]}" || true
        fi
      ''}
    ''
  );
}
