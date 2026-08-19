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

    # Second MTP engine for A/B testing (Homebrew CLI, not in nixpkgs). Same
    # Qwen 3.8 27B class, different quant/runtime. Serve on :8083.
    omlx = {
      npm = "@ai-sdk/openai-compatible";
      name = "oMLX Qwen (local, MTP)";
      options = {
        baseURL = "http://127.0.0.1:8083/v1";
        apiKey = "local";
      };
      models = {
        "Qwen3.8-27B-oQ4e-mtp" = {
          name = "Qwen3.8 27B oQ4e-MTP (oMLX, local)";
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

  # Built via uv2nix (nixos/common/pkgs/mtplx) instead of `uvx --from mtplx`,
  # so it's a real Nix-store package pinned by uv.lock rather than a
  # runtime PyPI fetch. Darwin-only (see overlays.nix); do not reference
  # unstable.mtplx outside of a Darwin-guarded context.
  serveQwen = pkgs.writeShellScriptBin "serve-qwen" ''
    set -euo pipefail

    # MTPLX uses MLX-formatted Hugging Face repos instead of GGUF files.
    # Official models from MTPLX author: huggingface.co/Youssofal
    MODEL="''${QWEN_MLX:-Youssofal/Qwen3.8-27B-MTPLX-Optimized-Speed}"
    CACHE_DIR="$HOME/ai/models"

    echo "Starting MTPLX (Qwen 3.8 Optimized Speed) on :8081 ..."

    mkdir -p "$CACHE_DIR"

    # `mtplx quickstart` is the headless OpenAI/Anthropic server entry point;
    # `mtplx start` is interactive-only (picks model/mode/surface, then drops
    # into chat). `pull` is a separate explicit step so first-run downloads
    # happen predictably rather than inline during quickstart.
    #
    # `--paged-kv-quantization q4` is the TurboQuant-style KV cache: attention
    # Keys stay at 8-bit while Values are crushed to 4-bit, which is what
    # stretches the 27B model to a huge context window on 48 GB of RAM.
    #
    # CAVEAT (observed 2.8.2, 2026-08-19): with MTP on, startup logs
    #   compiled-verify prewarm {"buckets": [], "skipped": ["quantized_paged_kv"]}
    # i.e. the quantised paged-KV variant is skipped in the compiled verify
    # path, so this flag is at best partially in effect. oMLX hits the same
    # collision from the other side (its MTP verify falls back on TurboQuant
    # layers), which suggests speculative verify over a quantised KV cache is
    # an inherent conflict rather than a bug in either engine. Treat MTP and
    # cheap KV as mutually exclusive until measured otherwise.
    # mtplx's prefix cache is its "session bank". By default it auto-sizes to
    # half the post-model RAM surplus — logged at startup as e.g.
    #   session-bank budget: 14.1G total, 8.0G per-session cap, 24 entries max
    # That answers a question the engine A/B needed: mtplx DOES do prefix
    # caching, so oMLX's SSD cache is not a unique advantage.
    #
    # It is also a large standing reservation on a 48 GB box: 19.8G of weights
    # plus a 14.1G bank leaves noticeably less room for context than oMLX's
    # ~16.0G model. Shrink the bank to trade cache capacity for context, or
    # grow it to hold more sessions:
    #   MTPLX_SESSION_BANK_MAX_BYTES=8G MTPLX_SESSION_BANK_PER_SESSION_BYTES=4G serve-qwen
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

  # oMLX (Homebrew CLI, not in nixpkgs) as a second MTP test engine: same
  # Qwen 3.8 27B class as serve-qwen but a different runtime, for A/B
  # testing. Serves on :8083 (mtplx=8081, gemma=8082). Two 27B servers
  # can't share 48 GB — run this instead of serve-qwen, not alongside it.
  serveOmlx = pkgs.writeShellScriptBin "serve-omlx" ''
    set -euo pipefail

    export OMLX_MODEL_DIR="$HOME/ai/models/omlx"

    # Was root4k/Huihui-Qwen3.8-27B-abliterated-oQ4e-mtp. Abliteration removes
    # the refusal direction from the weights — a lossy edit that costs
    # instruction-following for a property agentic coding never uses (you don't
    # get refused writing Nix modules). This is the first-party oQ4e build from
    # the oMLX author (HF Jundot = github.com/jundot/omlx, the same upstream as
    # the Homebrew tap in darwin/common.nix). Identical spec to the abliterated
    # build it replaces — 4-bit affine, group 64, the same 166 tensors promoted
    # to 5-bit, MTP with 1 nextn layer, 262144 native context, 17.0 GB — so the
    # only difference is the base weights.
    #
    # NOTE ON MTP: it does not currently buy anything here (11.0 vs 9.6 tok/s
    # baseline is noise, versus 18.3 for mtplx). Qwen3.8-27B *is* a VLM —
    # every build on HF, including Qwen/Qwen3.8-27B itself, is
    # Qwen3_5ForConditionalGeneration with a vision tower — so oMLX routes it
    # down the VLM engine path where draft acceptance is poor. Switching oQ4e
    # publishers does not change that; they are all the same architecture.
    #
    # The one candidate that might change it is a vision-stripped build:
    #   OMLX_MODEL_REPO=lukaskremla/Qwen3.8-27B-4bit-MLX-TextOnly serve-omlx
    # (15.2 GB, vision_config removed, mtp_num_hidden_layers still 1). Whether
    # oMLX then picks its text engine is unverified — the architecture string
    # is unchanged, so it may not. It is also plain MLX 4-bit rather than oQ4e,
    # i.e. no imatrix 5-bit promotions, so quality may be slightly lower.
    # Worth an A/B with `bench-llm` before adopting; that is exactly the
    # decode-vs-quality question the harness exists to answer.
    MODEL_REPO="''${OMLX_MODEL_REPO:-Jundot/Qwen3.8-27B-oQ4e-mtp}"
    NAME="''${MODEL_REPO##*/}"
    MODEL_ID="''${OMLX_MODEL_ID:-$NAME}"

    OMLX_BIN="''${OMLX_BIN:-}"
    if [ -z "$OMLX_BIN" ]; then
      OMLX_BIN="$(command -v omlx 2>/dev/null || true)"
      [ -z "$OMLX_BIN" ] && OMLX_BIN="/opt/homebrew/opt/omlx/bin/omlx"
    fi

    mkdir -p "$OMLX_MODEL_DIR/$NAME"
    if [ ! -f "$OMLX_MODEL_DIR/$NAME/config.json" ]; then
      echo "oMLX: downloading $MODEL_REPO (~17 GB, one-time) ..."
      export PATH="${pkgs.uv}/bin:$PATH"
      uvx --from huggingface_hub hf download "$MODEL_REPO" --local-dir "$OMLX_MODEL_DIR/$NAME"
    fi

    # oMLX enables MTP and TurboQuant per model via ~/.omlx/model_settings.json
    # (read at startup). Combining them on the Qwen 3.8 oQ4e-MTP build crashed
    # in 0.6.1 ('TurboQuantMSEState' has no 'ndim'); 0.6.2 made it not crash by
    # having MTP verify fall back to the compatible attention path — which is
    # NOT the same as the two stacking.
    #
    # Evidence they do not stack: oMLX rejected a 72k-token prefill on
    # 2026-08-19 needing "KV+SDPA 15.40 GB", i.e. ~213 KB/token. TurboQuant q4
    # KV on this architecture should cost ~16 KB/token (2 x 4 kv_heads x 256
    # head_dim x 16 full-attention layers of 64). Being ~13x over that suggests
    # KV is not actually being quantised while MTP is on.
    #
    # That makes MTP-vs-context a real trade rather than a free win, so both
    # are switchable for A/B with `bench-llm`:
    #   OMLX_MTP=0 serve-omlx            # favour context (TurboQuant only)
    #   OMLX_TURBOQUANT=0 serve-omlx     # favour decode  (MTP only)
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
print("model_settings: mtp=%s turboquant=%s bits=%s"
      % (m["mtp_enabled"], m["turboquant_kv_enabled"], m["turboquant_kv_bits"]))
' "$MODEL_ID" "''${OMLX_MTP:-1}" "''${OMLX_TURBOQUANT:-1}" "''${OMLX_TURBOQUANT_BITS:-4}"

    # oMLX derives its caps as a fraction of min(this guard, the Metal wired
    # limit): soft = 85%, hard = 95%. Confirmed against its dashboard on
    # 2026-08-19, which read "37.4 GB soft / 41.8 GB hard" — exactly 44 x 0.85
    # and 44 x 0.95, so this guard is what binds today, not Metal.
    #
    # (37.4 GB is also, coincidentally, Apple's default wired limit on a 48 GB
    # machine. Do not read that number as evidence the sysctl in
    # darwin/common.nix failed to apply — verify with `sysctl
    # iogpu.wired_limit_mb` instead, which reports 46000 = 44.9 GiB.)
    #
    # Default raised 44 -> 46 so the Metal ceiling binds instead, giving a
    # prefill cap of 42.7 GB rather than 41.8 GB. That is only ~4k extra tokens
    # at the measured ~240 KB/token, but it is free.
    #
    # It is NOT enough to rescue a real failure seen on 2026-08-19: a 72k-token
    # opencode session was rejected needing 43.55 GB (current 28.14 + KV+SDPA
    # 15.40) against a 41.80 GB ceiling. Even with Metal binding, 42.66 GB
    # falls short. Reaching 43.55 GB would need iogpu.wired_limit_mb ~46940,
    # leaving ~2 GiB for all of macOS — not worth the instability. The real
    # lever on context is cutting KV cost per token (see OMLX_MTP above), not
    # this ceiling.
    #
    # Note that ~240 KB/token is far above the ~16 KB/token the attention KV
    # alone should cost (2 x 4 kv_heads x 256 head_dim x 16 full-attention
    # layers of 64, at q4). Most of the growth is prefill working memory and
    # linear-attention state, not stored KV — do not size context from the KV
    # figure. Overridable so `bench-llm` runs can sweep it:
    #   OMLX_MEMORY_GUARD_GB=46 serve-omlx
    GUARD_GB="''${OMLX_MEMORY_GUARD_GB:-46}"

    echo "Starting oMLX (Qwen 3.8 oQ4e-MTP) on :8083, memory guard ''${GUARD_GB}GB ..."
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
