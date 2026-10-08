{ pkgs, lib, inputs, ... }:
let
  tmuxUpdateEnv = pkgs.writeShellScriptBin "tmux-update-env" ''
    SOCK=$(tmux show-environment -g SSH_AUTH_SOCK | cut -d= -f2)
    if [ -n "$SOCK" ] && [ "$SOCK" != "$HOME/.ssh/ssh_auth_sock" ] && [ -S "$SOCK" ]; then
        mkdir -p "$HOME/.ssh"
        ln -sf "$SOCK" "$HOME/.ssh/ssh_auth_sock"
    fi
  '';

  # flake inputs (flake.lock pins them; `pins update <name>` bumps them)
  inputVersion = src:
    let d = src.lastModifiedDate;
    in "unstable-${lib.substring 0 4 d}-${lib.substring 4 2 d}-${lib.substring 6 2 d}";

  tmux-agent-indicator = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "agent-indicator";
    version = inputVersion inputs.tmux-agent-indicator;
    src = inputs.tmux-agent-indicator;
    postInstall = ''
      cd $out/share/tmux-plugins/agent-indicator
      ln -s agent-indicator.tmux agent_indicator.tmux
      substituteInPlace scripts/agent-state.sh \
        --replace 'tmux display-message -d "$duration" "$message" || true' 'true' \
        --replace 'tmux display-message "$message" || true' 'true'
    '';
  };

  # tmux-resurrect patched:
  #  - src from upstream master via the flake input (nixpkgs pins 2022-05-01,
  #    which lacks the `*` argument restore fixes needed to relaunch agent CLIs)
  #  - empty pane titles fall back to the cwd in pane_format; otherwise bash
  #    `read` with IFS=<tab> collapses the empty title field, shifting every
  #    later column (dir becomes "1"), and restore silently falls back to $HOME
  resurrectPatched = pkgs.tmuxPlugins.resurrect.overrideAttrs (old: {
    name = "tmuxplugin-resurrect-${inputVersion inputs.tmux-resurrect}";
    src = inputs.tmux-resurrect;
    # upstream tests symlink into the tmux-test submodule, which GitHub
    # archives do not include; drop them before fixup flags broken symlinks
    postInstall = (old.postInstall or "") + ''
      rm -rf $out/share/tmux-plugins/resurrect/tests $out/share/tmux-plugins/resurrect/run_tests
    '';
    postPatch = (old.postPatch or "") + ''
      substituteInPlace scripts/save.sh \
        --replace-fail 'format+="#{pane_title}"' 'format+="#{?pane_title,#{pane_title},#{pane_current_path}}"'
    '';
  });

  # Relaunch agent CLIs from tmux-resurrect: pass through an explicit resume
  # argument (opencode -s/--session, claude -r/--resume, agy --conversation)
  # if one was saved, otherwise continue the most recent conversation in the
  # pane's directory.
  #
  # opencode's saved argv does not name the conversation that was on screen
  # (launched bare => `opencode`), so `--continue` can pick a different, more
  # recently updated session in the same project. Resolve the exact session
  # from the restored pane title (`OC | <title>`, set from the save before the
  # command runs) via `opencode session list --format json`; fall back to
  # --continue when the title is missing, truncated or unknown. A saved
  # `--continue` is treated as fallback (not as explicit) for opencode.
  agentResume = pkgs.writeShellScriptBin "agent-resume" ''
    set -u
    cmd="''${1:-}"
    if [ -z "$cmd" ]; then
      echo "usage: agent-resume <agent-cli> [args...]" >&2
      exit 1
    fi
    shift

    # an explicit session/conversation id wins; --continue does not, since it
    # is exactly the ambiguous fallback we are trying to replace
    explicit=""
    continue_seen=""
    for arg in "$@"; do
      case "$arg" in
        -c|--continue) continue_seen=1 ;;
        -s|--session|--session=*|-r|--resume|--resume=*|--conversation|--conversation=*)
          explicit=1
          ;;
      esac
    done
    if [ -n "$explicit" ]; then
      exec "$cmd" "$@"
    fi

    if [ "''${cmd##*/}" = "opencode" ] && [ -n "''${TMUX_PANE:-}" ] && command -v jq >/dev/null 2>&1; then
      pane_title="$(tmux display-message -p -t "$TMUX_PANE" '#{pane_title}' 2>/dev/null || true)"
      case "$pane_title" in
        "OC | "*)
          want="''${pane_title#OC | }"
          want="''${want%…}"
          sessions="$("$cmd" session list --format json 2>/dev/null || true)"
          id="$(printf '%s' "$sessions" | jq -r --arg want "$want" '
            (map(select(.title == $want)) | .[0].id) //
            (map(select(.title | startswith($want))) | .[0].id) // empty' 2>/dev/null || true)"
          if [ -n "$id" ] && [ "$id" != "null" ]; then
            args=()
            for arg in "$@"; do
              case "$arg" in
                -c|--continue) ;;
                *) args+=("$arg") ;;
              esac
            done
            exec "$cmd" -s "$id" "''${args[@]}"
          fi
          ;;
      esac
    fi

    if [ -n "$continue_seen" ]; then
      exec "$cmd" "$@"
    fi
    exec "$cmd" --continue "$@"
  '';

  # Rewrite tmux-resurrect save files so agent panes carry their exact
  # conversation id instead of relying on `--continue` guessing the most
  # recently updated one:
  #  - claude: ~/.claude/sessions/<pid>.json records sessionId + the tmux pane
  #  - agy: the running process holds <data>/presence/<conversation-id>.lock
  # Runs as @resurrect-hook-post-save-layout with the save file as $1.
  agentPinSessions = pkgs.writeShellScriptBin "agent-pin-sessions" ''
    set -u

    save_file="''${1:?usage: agent-pin-sessions <resurrect-save-file>}"
    [ -f "$save_file" ] || exit 0

    jq="${pkgs.jq}/bin/jq"
    pane_map="$(mktemp)"
    pins="$(mktemp)"
    trap 'rm -f "$pane_map" "$pins"' EXIT

    tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}	#{pane_id}	#{pane_pid}' >"$pane_map" 2>/dev/null || exit 0
    [ -s "$pane_map" ] || exit 0

    pane_key_for_pid() {
      local pid="$1" key
      while [ -n "$pid" ] && [ "$pid" != 0 ] && [ "$pid" != 1 ]; do
        key="$(awk -F'\t' -v p="$pid" '$3 == p { print $1; exit }' "$pane_map")"
        if [ -n "$key" ]; then
          printf '%s' "$key"
          return 0
        fi
        pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
      done
      return 1
    }

    if [ -x "$jq" ]; then
      for session_json in "$HOME"/.claude/sessions/*.json; do
        [ -f "$session_json" ] || continue
        info="$("$jq" -r '[.pid // "", .sessionId // "", .tmux // ""] | @tsv' "$session_json" 2>/dev/null)" || continue
        IFS=$'\t' read -r pid session_id tmux_ref <<<"$info"
        [ -n "$pid" ] && [ -n "$session_id" ] || continue
        kill -0 "$pid" 2>/dev/null || continue
        key=""
        if [ -n "$tmux_ref" ]; then
          pane_id="''${tmux_ref##*.}"
          key="$(awk -F'\t' -v id="$pane_id" '$2 == id { print $1; exit }' "$pane_map")"
        fi
        [ -n "$key" ] || key="$(pane_key_for_pid "$pid" || true)"
        [ -n "$key" ] || continue
        printf '%s\t--resume %s\n' "$key" "$session_id" >>"$pins"
      done
    fi

    lsof_bin="$(command -v lsof 2>/dev/null || true)"
    [ -n "$lsof_bin" ] || [ ! -x /usr/sbin/lsof ] || lsof_bin=/usr/sbin/lsof
    if [ -n "$lsof_bin" ]; then
      for pid in $(pgrep -x agy 2>/dev/null); do
        conversation_id="$("$lsof_bin" -p "$pid" 2>/dev/null | sed -n 's#.*/presence/\([0-9a-fA-F][0-9a-fA-F-]*\)\.lock.*#\1#p' | awk 'NR == 1 { print }')"
        [ -n "$conversation_id" ] || continue
        key="$(pane_key_for_pid "$pid" || true)"
        [ -n "$key" ] || continue
        printf '%s\t--conversation %s\n' "$key" "$conversation_id" >>"$pins"
      done
    fi

    [ -s "$pins" ] || exit 0

    awk -F'\t' -v OFS='\t' -v pins="$pins" '
      BEGIN {
        while ((getline line < pins) > 0) {
          split(line, pair, "\t")
          pin[pair[1]] = pair[2]
        }
      }
      /^pane/ {
        key = $2 ":" $3 "." $6
        extra = pin[key]
        if (extra != "" && $11 != "" && $11 != ":") {
          cmd = substr($11, 2)
          gsub(/[ \t]+(-c|--continue)([ \t]+|$)/, " ", cmd)
          gsub(/[ \t]+(-r|--resume)[ \t]+[^-][^ \t]*/, " ", cmd)
          gsub(/[ \t]+(-r|--resume)([ \t]+|$)/, " ", cmd)
          gsub(/[ \t]+--conversation[ \t]+[^-][^ \t]*/, " ", cmd)
          gsub(/[ \t]+--(resume|conversation)=[^ \t]*/, " ", cmd)
          sub(/^[ \t]+/, "", cmd)
          sub(/[ \t]+$/, "", cmd)
          $11 = ":" cmd " " extra
        }
        print
        next
      }
      { print }
    ' "$save_file" >"$save_file.tmp.$$" && mv "$save_file.tmp.$$" "$save_file"
  '';
in
{

  programs.tmux = {
    enable = true;
    mouse = true;
    # Use system zsh on macOS (in /etc/shells) and nix zsh on Linux
    shell = if pkgs.stdenv.isDarwin then "/bin/zsh" else "${pkgs.zsh}/bin/zsh";
    terminal = "xterm-256color";
    clock24 = true;
    baseIndex = 1;
    escapeTime = 0;
    keyMode = "vi";
    extraConfig = ''
      ${lib.readFile ./tmux/tmux.conf}
      set-hook -g client-attached 'run-shell "${tmuxUpdateEnv}/bin/tmux-update-env"'

      # Pin exact agent conversations (claude/agy) into every resurrect save
      set -g @resurrect-hook-post-save-layout '${agentPinSessions}/bin/agent-pin-sessions'

      ${lib.optionalString pkgs.stdenv.isDarwin ''
        # Tmux Agent Indicator macOS integration
        set -g @agent-indicator-notification-command "sketchybar --trigger ai_agent_update; /usr/bin/open -g \"hammerspoon://nanowm?cmd=agentState&state=$AGENT_STATE&name=$AGENT_NAME\"; case $AGENT_STATE in done|off) sleep 3 && sketchybar --trigger ai_agent_update;; esac"
        # Trigger sketchybar refresh on pane exit (catches agent exits without SessionEnd hooks, e.g. Claude)
        set-hook -g pane-exited "run-shell -b 'sketchybar --trigger ai_agent_update 2>/dev/null'"
      ''}
      # AI agent switcher: fzf --tmux popup listing all tracked agent panes
      bind-key A run-shell -b "tmux-agent-switcher"
      # Review the last agent turn in this pane's worktree (agent-checkpoint +
      # diffview); q closes the review and the popup
      bind-key D display-popup -E -w 95% -h 95% -d "#{pane_current_path}" "nvim -c 'let g:agent_review_popup = 1' -c AgentReview"
    '';
    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
      # vim-tmux-navigator
      tmux-fzf
      resurrectPatched
      continuum
      jump
      better-mouse-mode
      prefix-highlight
      urlview
      { plugin = tmux-agent-indicator; }
      # { plugin = inputs.minimal-tmux.packages.${pkgs.system}.default; }
    ];
  };

  home.packages = [
    tmuxUpdateEnv
    agentResume
    agentPinSessions
    (pkgs.writeShellScriptBin "tmux-agent-switcher" (lib.readFile ./scripts/tmux-agent-switcher))
    (pkgs.writeShellScriptBin "agent-state" ''
      "${tmux-agent-indicator}/share/tmux-plugins/agent-indicator/scripts/agent-state.sh" "$@"

      ${lib.optionalString pkgs.stdenv.isDarwin ''
        # Notify Hammerspoon of agent state changes for hs.alert notifications
        AGENT="" STATE=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --agent) AGENT="$2"; shift 2 ;;
            --state) STATE="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        if [ -n "$AGENT" ] && [ -n "$STATE" ]; then
          if pgrep -x "Hammerspoon" > /dev/null; then
            # nanowm's URL handler, not `hs -c`: a backgrounded hs -c per state change could
            # overlap and wedge Hammerspoon's IPC port
            /usr/bin/open -g "hammerspoon://nanowm?cmd=agentState&state=$STATE&name=$AGENT"
          fi
        fi
      ''}
    '')
  ];

}
