#!/bin/bash

# ═══════════════════════════════════════════════════════════════
# ai_agents.sh — AI Coding Assistant Session Monitor
#
# Detects running Claude Code (.claude-wrapped) and Gemini CLI
# (node + /bin/gemini) sessions and checks their status.
#
# Status colors:
#   ● yellow  — working  (active API connection)
#   ● red     — confirm  (pane shows yes/no or allow/deny prompt)
#   ● purple  — waiting  (state files updated < 30 min, needs reply)
#   ○ gray    — idle     (session open, no recent activity)
# ═══════════════════════════════════════════════════════════════

MAX_SLOTS=8

# Close popup on mouse.exited.global (auto-fired when leaving bar)
if [ "$SENDER" = "mouse.exited.global" ]; then
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi

# ──────────────────────────────────────────────────────────────
# 1. Detect sessions
# ──────────────────────────────────────────────────────────────

# Claude Code: nix wraps binary as ".claude-wrapped" (ucomm)
CLAUDE_PIDS=$(ps -eo pid,ucomm | awk '$2 == ".claude-wrapped" {print $1}')

# Gemini CLI: runs as "node /path/to/bin/gemini".
# Gemini spawns a child node process with the same args, so keep only
# session roots — PIDs whose parent is not also a gemini process.
_ALL_GEMINI=$(ps -eo pid,ppid,ucomm,args | awk '$3 ~ /^node/ && $NF ~ /\/bin\/gemini$/ {print $1, $2}')
GEMINI_PIDS=$(echo "$_ALL_GEMINI" | awk '
  { pid[NR]=$1; ppid[NR]=$2 }
  END {
    for (i=1; i<=NR; i++) {
      is_child=0
      for (j=1; j<=NR; j++) { if (ppid[i]==pid[j]) { is_child=1; break } }
      if (is_child == 0) print pid[i]
    }
  }
')

ALL_PIDS=$(printf '%s\n%s' "$CLAUDE_PIDS" "$GEMINI_PIDS" | grep -v '^$')

CLAUDE_COUNT=$(echo "$CLAUDE_PIDS" | grep -c '^[0-9]' 2>/dev/null || echo 0)
GEMINI_COUNT=$(echo "$GEMINI_PIDS" | grep -c '^[0-9]' 2>/dev/null || echo 0)
TOTAL=$((CLAUDE_COUNT + GEMINI_COUNT))

if [ "$TOTAL" -eq 0 ]; then
  sketchybar --set "$NAME" drawing=off popup.drawing=off
  exit 0
fi

# ──────────────────────────────────────────────────────────────
# 2. Batch status lookups
# ──────────────────────────────────────────────────────────────

PID_LIST=$(echo "$ALL_PIDS" | tr '\n' ',' | sed 's/,$//')

# "PID /cwd/path" pairs for all sessions
CWD_DATA=$(lsof -a -p "$PID_LIST" -d cwd 2>/dev/null \
  | awk 'NR>1 {print $2, $NF}')

# Process table and tmux panes (fetched once, shared by helpers below)
PROC_TABLE=$(ps -eo pid,ppid)
TMUX_PANES=$(tmux list-panes -a -F '#{pane_pid} #{pane_id}' 2>/dev/null)

# ──────────────────────────────────────────────────────────────
# 3. Helpers for confirm detection
# ──────────────────────────────────────────────────────────────

# Walk the process tree to find the tmux pane containing a given PID.
get_pane_for_pid() {
  local pid="$1" cur="$pid" ancestors="$pid " i=0
  while [ "$i" -lt 20 ]; do
    cur=$(printf '%s\n' "$PROC_TABLE" | awk -v p="$cur" '$1==p{print $2;exit}')
    [ -z "$cur" ] || [ "$cur" = "1" ] || [ "$cur" = "0" ] && break
    ancestors="${ancestors}${cur} "
    i=$((i+1))
  done
  while IFS=' ' read -r pane_pid pane_id; do
    case " $ancestors " in
      *" $pane_pid "*) echo "$pane_id"; return;;
    esac
  done <<< "$TMUX_PANES"
}

# Return 0 (true) if the given pane CONTENT shows a confirmation prompt.
# Caller captures content and passes it in (avoids redundant tmux calls).
content_is_confirm() {
  local content="$1"
  # Claude Code permission dialog button labels (capital-A, exact phrases)
  printf '%s\n' "$content" | grep -qF 'Allow once' && return 0
  printf '%s\n' "$content" | grep -qF 'Allow for this session' && return 0
  printf '%s\n' "$content" | grep -qF 'Allow in project' && return 0
  # Claude Code command confirmation dialog (numbered Yes/No options)
  printf '%s\n' "$content" | grep -qF 'Do you want to proceed?' && return 0
  # TUI cursor on a STANDALONE option keyword — nothing else on the line.
  # Covers Gemini's "❯ Yes" / "❯ No" menus.
  printf '%s\n' "$content" | grep -qiE '^[[:space:]]*(❯|›)[[:space:]]*(yes|no|deny)[[:space:]]*$' && return 0
  # Classic prompts
  printf '%s\n' "$content" | grep -qE '\[y/n\]|\[Y/n\]|\(y/n\)' && return 0
  return 1
}

# Return the ESTABLISHED TCP connection count for a PID and its immediate children.
agent_conn_count() {
  local pid="$1"
  local pids="$pid"
  local children
  children=$(awk -v p="$pid" '$2==p{printf ",%s",$1}' <<< "$PROC_TABLE")
  pids="${pids}${children}"
  lsof -a -p "$pids" -i 2>/dev/null | grep -c ESTABLISHED
}

# ──────────────────────────────────────────────────────────────
# 4. Per-session status → update popup slots
# ──────────────────────────────────────────────────────────────

SLOT=0
# Priority: idle=0 < recent=1 < working=2 < confirm=3
AGG_PRIORITY=0
AGGREGATE="idle"

update_aggregate() {
  local priority="$1" state="$2"
  if [ "$priority" -gt "$AGG_PRIORITY" ]; then
    AGG_PRIORITY=$priority
    AGGREGATE="$state"
  fi
}

for pid in $ALL_PIDS; do
  [ -z "$pid" ] && continue
  SLOT=$((SLOT + 1))
  [ "$SLOT" -gt "$MAX_SLOTS" ] && break

  # Reset per-agent state
  DOT="" COLOR=""

  # Tool type
  TYPE="C"
  echo "$GEMINI_PIDS" | grep -qw "$pid" && TYPE="G"

  # Working directory
  CWD=$(echo "$CWD_DATA" | awk -v p="$pid" '$1==p {print $2; exit}')
  PROJECT=$(basename "$CWD" 2>/dev/null || echo "?")

  # Capture pane content once (used for both confirm and Gemini working checks)
  PANE_ID=$(get_pane_for_pid "$pid")
  PANE_CONTENT=""
  [ -n "$PANE_ID" ] && PANE_CONTENT=$(tmux capture-pane -t "$PANE_ID" -p 2>/dev/null | tail -20)

  # 1. Confirm: pane shows yes/no or allow/deny prompt
  if [ -n "$PANE_CONTENT" ] && content_is_confirm "$PANE_CONTENT"; then
    DOT="●"; COLOR="0xffe06c75"   # red — needs your immediate input
    update_aggregate 3 "confirm"

  # 2a. Claude working: keeps 1 persistent TCP conn when idle (HTTP/2 keep-alive).
  #     Active tool use / streaming adds more → conns > 1 means working.
  elif [ "$TYPE" = "C" ] && [ "$(agent_conn_count "$pid")" -gt 1 ]; then
    DOT="●"; COLOR="0xffe0af68"
    update_aggregate 2 "working"

  # 2b. Gemini working: API connections are too short-lived and [INSERT] status
  #     bar is always visible. Use CPU usage as a proxy: idle → 0%, working → >0%.
  elif [ "$TYPE" = "G" ]; then
    _pids="$pid"
    _children=$(awk -v p="$pid" '$2==p{printf ",%s",$1}' <<< "$PROC_TABLE")
    _pids="${_pids}${_children}"
    _cpu=$(ps -p "$_pids" -o %cpu= 2>/dev/null | awk '{s+=$1}END{printf "%.0f", s*10}')
    if [ "${_cpu:-0}" -gt 5 ]; then   # > 0.5% CPU
      DOT="●"; COLOR="0xffe0af68"
      update_aggregate 2 "working"
    fi
  fi

  # 3. Fall back if not already set
  if [ -z "$DOT" ]; then
    STATE_DIR=""
    if [ "$TYPE" = "C" ] && [ -n "$CWD" ]; then
      STATE_DIR="$HOME/.claude/projects/$(echo "$CWD" | tr '/' '-')"
    elif [ "$TYPE" = "G" ] && [ -n "$CWD" ]; then
      STATE_DIR="$HOME/.gemini/tmp/$(basename "$CWD")"
    fi

    if [ -n "$STATE_DIR" ] && \
       find "$STATE_DIR" -mmin -30 2>/dev/null | grep -q .; then
      DOT="●"; COLOR="0xff7b5cff"   # purple — waiting for your reply
      update_aggregate 1 "recent"
    else
      DOT="○"; COLOR="0xff565f89"   # gray — idle
    fi
  fi

  # Write PID file so the click_script knows which agent to focus
  echo "$pid" > "/tmp/sketchybar_ai_agent_${SLOT}.pid"

  sketchybar --set "ai_agents.popup.${SLOT}" \
    drawing=on \
    icon="$DOT" \
    icon.color="$COLOR" \
    label="${TYPE}: $PROJECT"
done

# Hide unused slots and clear their PID files
i=$((SLOT + 1))
while [ "$i" -le "$MAX_SLOTS" ]; do
  sketchybar --set "ai_agents.popup.${i}" drawing=off
  rm -f "/tmp/sketchybar_ai_agent_${i}.pid"
  i=$((i + 1))
done

# ──────────────────────────────────────────────────────────────
# 5. Update bar item (count + aggregate color)
# ──────────────────────────────────────────────────────────────

LABEL=""
[ "$CLAUDE_COUNT" -gt 0 ] && LABEL="C:${CLAUDE_COUNT}"
[ "$GEMINI_COUNT" -gt 0 ] && LABEL="${LABEL:+$LABEL }G:${GEMINI_COUNT}"

case "$AGGREGATE" in
  confirm) ICON_COLOR="0xffe06c75" ;;   # red    — needs immediate input
  working) ICON_COLOR="0xffe0af68" ;;   # yellow — generating
  recent)  ICON_COLOR="0xff7b5cff" ;;   # purple — waiting for reply
  idle)    ICON_COLOR="0xff565f89" ;;   # gray   — nothing needs attention
esac

sketchybar --set "$NAME" \
  drawing=on \
  label="$LABEL" \
  icon.color="$ICON_COLOR"
