#!/bin/bash

# ═══════════════════════════════════════════════════════════════
# ai_agents.sh — AI Coding Assistant Session Monitor
#
# Detects sessions using tmux-agent-indicator global environment
# or process-based fallback (for Gemini/Claude without hooks).
# ═══════════════════════════════════════════════════════════════

MAX_SLOTS=8

# Close popup on mouse.exited.global (auto-fired when leaving bar)
if [ "$SENDER" = "mouse.exited.global" ]; then
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi

# ──────────────────────────────────────────────────────────────
# 1. Detect sessions using tmux-agent-indicator variables (global environment)
# ──────────────────────────────────────────────────────────────

# Get global tmux environment variables starting with TMUX_AGENT_PANE_
AGENT_ENV=$(tmux show-environment -g 2>/dev/null | grep '^TMUX_AGENT_PANE_')

# Get all pane info to match CWD, PID, and TTY for fallback detection
ALL_PANES=$(tmux list-panes -a -F '#{pane_id}|#{pane_pid}|#{pane_tty}|#{pane_current_path}' 2>/dev/null)

if [ -z "$AGENT_ENV" ] && [ -z "$ALL_PANES" ]; then
  sketchybar --set "$NAME" drawing=off background.drawing=off popup.drawing=off
  exit 0
fi

# ──────────────────────────────────────────────────────────────
# 2. Per-session status → update popup slots
# ──────────────────────────────────────────────────────────────

SLOT=0
# Priority: idle=0 < done=1 < running=2 < needs-input=3
AGG_PRIORITY=0
AGGREGATE="idle"
CLAUDE_ACTIVE=0
GEMINI_ACTIVE=0
PROCESSED_PANES=""

update_aggregate() {
  local priority="$1" state="$2"
  if [ "$priority" -gt "$AGG_PRIORITY" ]; then
    AGG_PRIORITY=$priority
    AGGREGATE="$state"
  fi
}

# Return 0 (true) if the given pane content shows a confirmation prompt.
content_is_confirm() {
  local content="$1"
  # Claude Code permission dialog button labels
  printf '%s\n' "$content" | grep -qF 'Allow once' && return 0
  printf '%s\n' "$content" | grep -qF 'Allow for this session' && return 0
  printf '%s\n' "$content" | grep -qF 'Allow in project' && return 0
  printf '%s\n' "$content" | grep -qF 'Do you want to proceed?' && return 0
  # Gemini cursor or menu options
  printf '%s\n' "$content" | grep -qiE '^[[:space:]]*(❯|›)[[:space:]]*(yes|no|deny)[[:space:]]*$' && return 0
  printf '%s\n' "$content" | grep -qE '\[y/n\]|\[Y/n\]|\(y/n\)' && return 0
  # Gemini menu list (e.g., "3. Modify with external editor")
  printf '%s\n' "$content" | grep -qE '[0-9]\. ' && return 0
  return 1
}

# 2a. First, process explicit states from environment (hooks)
if [ -n "$AGENT_ENV" ]; then
  PANE_IDS_ENV=$(echo "$AGENT_ENV" | grep -o '%[0-9]*' | sort -u)
  for pane_id in $PANE_IDS_ENV; do
    status=$(echo "$AGENT_ENV" | grep "^TMUX_AGENT_PANE_${pane_id}_STATE=" | cut -d= -f2)
    agent_name=$(echo "$AGENT_ENV" | grep "^TMUX_AGENT_PANE_${pane_id}_AGENT=" | cut -d= -f2)

    [ -z "$status" ] || [ "$status" = "off" ] && continue

    # Get pane info
    PANE_INFO=$(echo "$ALL_PANES" | grep "^${pane_id}|" | head -1)
    if [ -z "$PANE_INFO" ]; then
      # Cleanup stale environment variables
      tmux set-environment -ug "TMUX_AGENT_PANE_${pane_id}_STATE" 2>/dev/null
      tmux set-environment -ug "TMUX_AGENT_PANE_${pane_id}_AGENT" 2>/dev/null
      continue
    fi

    # Verify process is still there
    tty=$(echo "$PANE_INFO" | cut -d'|' -f3)
    tty_short=$(basename "$tty")
    AGENT_PROCESSES="claude .claude-wrapped gemini node aider cursor"
    found_proc=0
    for proc in $AGENT_PROCESSES; do
      if ps -t "$tty_short" -o command= 2>/dev/null | grep -qw "$proc"; then
        found_proc=1; break
      fi
    done

    if [ "$found_proc" -eq 0 ]; then
       tmux set-environment -ug "TMUX_AGENT_PANE_${pane_id}_STATE" 2>/dev/null
       tmux set-environment -ug "TMUX_AGENT_PANE_${pane_id}_AGENT" 2>/dev/null
       continue
    fi

    PROCESSED_PANES="$PROCESSED_PANES $pane_id"
    SLOT=$((SLOT + 1))
    [ "$SLOT" -gt "$MAX_SLOTS" ] && break

    cwd=$(echo "$PANE_INFO" | cut -d'|' -f4)
    PROJECT=$(basename "$cwd" 2>/dev/null || echo "?")

    # Override status if pane shows a confirm prompt
    PANE_CONTENT=$(tmux capture-pane -t "$pane_id" -p 2>/dev/null | tail -20)
    if [ -n "$PANE_CONTENT" ] && content_is_confirm "$PANE_CONTENT"; then
       status="needs-input"
    fi

    DOT="" COLOR=""
    case "$agent_name" in
      *Claude*|*claude*) TYPE="C" ;;
      *Gemini*|*gemini*|*Test*) TYPE="G" ;;
      *) TYPE="${agent_name:0:1}" ;;
    esac

    case "$status" in
      needs-input)
        DOT="●"; COLOR="0xffe06c75"   # red — needs input
        update_aggregate 3 "confirm"
        [[ "$TYPE" == "C" ]] && CLAUDE_ACTIVE=$((CLAUDE_ACTIVE + 1))
        [[ "$TYPE" == "G" ]] && GEMINI_ACTIVE=$((GEMINI_ACTIVE + 1))
        ;;
      running)
        DOT="●"; COLOR="0xffe0af68"   # yellow — working
        update_aggregate 2 "working"
        [[ "$TYPE" == "C" ]] && CLAUDE_ACTIVE=$((CLAUDE_ACTIVE + 1))
        [[ "$TYPE" == "G" ]] && GEMINI_ACTIVE=$((GEMINI_ACTIVE + 1))
        ;;
      done)
        DOT="●"; COLOR="0xff7b5cff"   # purple — waiting/recent
        update_aggregate 1 "recent"
        [[ "$TYPE" == "C" ]] && CLAUDE_ACTIVE=$((CLAUDE_ACTIVE + 1))
        [[ "$TYPE" == "G" ]] && GEMINI_ACTIVE=$((GEMINI_ACTIVE + 1))
        ;;
    esac

    echo "$pane_id" > "/tmp/sketchybar_ai_agent_${SLOT}.pane"
    sketchybar --set "ai_agents.popup.${SLOT}" drawing=on icon="$DOT" icon.color="$COLOR" label="${TYPE}: $PROJECT"
  done
fi

# 2b. Fallback: check all other panes for known agent processes (Gemini etc.)
AGENT_PROCESSES="claude .claude-wrapped gemini node aider cursor"
while IFS='|' read -r pane_id pid tty cwd; do
  [[ "$PROCESSED_PANES" =~ "$pane_id" ]] && continue
  [ "$SLOT" -gt "$MAX_SLOTS" ] && break

  found_agent=""
  tty_short=$(basename "$tty")

  # Get all processes on this TTY once
  TTY_PROCS=$(ps -t "$tty_short" -o command= 2>/dev/null)
  [ -z "$TTY_PROCS" ] && continue

  for proc in $AGENT_PROCESSES; do
    if echo "$TTY_PROCS" | grep -qw "$proc"; then
      if [ "$proc" = "node" ]; then
        if echo "$TTY_PROCS" | grep -qw "gemini"; then
           found_agent="Gemini"; break
        fi
        continue
      fi
      case "$proc" in
        *claude*) found_agent="Claude" ;;
        *gemini*) found_agent="Gemini" ;;
        *) found_agent="$proc" ;;
      esac
      break
    fi
  done

  [ -z "$found_agent" ] && continue

  SLOT=$((SLOT + 1))
  [ "$SLOT" -gt "$MAX_SLOTS" ] && break

  # Use CPU as proxy for working vs idle in fallback loop
  cpu_sum=$(ps -t "$tty_short" -o %cpu= 2>/dev/null | awk '{s+=$1}END{printf "%.0f", s*10}')

  status="idle"
  if [ "${cpu_sum:-0}" -gt 10 ]; then # > 1.0% CPU total on TTY
     status="running"
  fi

  # Check for confirmation prompts (red overrides yellow/gray)
  PANE_CONTENT=$(tmux capture-pane -t "$pane_id" -p 2>/dev/null | tail -20)
  if [ -n "$PANE_CONTENT" ] && content_is_confirm "$PANE_CONTENT"; then
     status="needs-input"
  fi

  case "$found_agent" in
    *Claude*|*claude*) TYPE="C" ;;
    *Gemini*|*gemini*) TYPE="G" ;;
    *) TYPE="${found_agent:0:1}" ;;
  esac

  DOT="" COLOR=""
  case "$status" in
    needs-input)
      DOT="●"; COLOR="0xffe06c75"   # red — needs input
      update_aggregate 3 "confirm"
      [[ "$TYPE" == "C" ]] && CLAUDE_ACTIVE=$((CLAUDE_ACTIVE + 1))
      [[ "$TYPE" == "G" ]] && GEMINI_ACTIVE=$((GEMINI_ACTIVE + 1))
      ;;
    running)
      DOT="●"; COLOR="0xffe0af68"   # yellow — working
      update_aggregate 2 "working"
      [[ "$TYPE" == "C" ]] && CLAUDE_ACTIVE=$((CLAUDE_ACTIVE + 1))
      [[ "$TYPE" == "G" ]] && GEMINI_ACTIVE=$((GEMINI_ACTIVE + 1))
      ;;
    idle)
      DOT="○"; COLOR="0xff565f89"   # gray — idle
      ;;
  esac

  PROJECT=$(basename "$cwd" 2>/dev/null || echo "?")
  echo "$pane_id" > "/tmp/sketchybar_ai_agent_${SLOT}.pane"
  sketchybar --set "ai_agents.popup.${SLOT}" drawing=on icon="$DOT" icon.color="$COLOR" label="${TYPE}: $PROJECT"
done <<< "$ALL_PANES"

# Hide unused slots and clear their PANE files
i=$((SLOT + 1))
while [ "$i" -le "$MAX_SLOTS" ]; do
  sketchybar --set "ai_agents.popup.${i}" drawing=off
  rm -f "/tmp/sketchybar_ai_agent_${i}.pane"
  i=$((i + 1))
done

# ──────────────────────────────────────────────────────────────
# 3. Update bar item (count + aggregate color)
# ──────────────────────────────────────────────────────────────

LABEL=""
[ "$CLAUDE_ACTIVE" -gt 0 ] && LABEL="C:${CLAUDE_ACTIVE}"
[ "$GEMINI_ACTIVE" -gt 0 ] && LABEL="${LABEL:+$LABEL }G:${GEMINI_ACTIVE}"

case "$AGGREGATE" in
  confirm) ICON_COLOR="0xffe06c75" ;;   # red    — needs immediate input
  working) ICON_COLOR="0xffe0af68" ;;   # yellow — generating
  recent)  ICON_COLOR="0xff7b5cff" ;;   # purple — waiting for reply
  idle)    ICON_COLOR="0xff565f89" ;;   # gray   — nothing needs attention
esac

# Always show widget if ANY slot is populated, but hide label if counts are 0
if [ "$SLOT" -eq 0 ]; then
  sketchybar --set "$NAME" drawing=off background.drawing=off popup.drawing=off
else
  sketchybar --set "$NAME" \
    drawing=on \
    background.drawing=on \
    label="$LABEL" \
    icon.color="$ICON_COLOR"
fi
