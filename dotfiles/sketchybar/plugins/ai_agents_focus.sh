#!/bin/bash

# Called when a popup slot is clicked.
# Reads the pane ID, finds its tmux session/window, switches to it,
# and focuses the terminal (auto-detected from the tmux client process tree).

SLOT=$(echo "$NAME" | grep -o '[0-9]*$')
PANE_FILE="/tmp/sketchybar_ai_agent_${SLOT}.pane"
[ -f "$PANE_FILE" ] || exit 0
PANE_ID=$(cat "$PANE_FILE" 2>/dev/null)
[ -z "$PANE_ID" ] && exit 0

sketchybar --set ai_agents popup.drawing=off

# ── find tmux session and window from pane_id ────────────────────────────────
read -r session win_idx < <(tmux list-panes -a -F '#{session_name} #{window_index}' -f "#{m:#{pane_id},$PANE_ID}" 2>/dev/null)

# Validate the pane still exists
[ -z "$session" ] && exit 0

# Switch tmux to the agent's pane
tmux switch-client -t "$session"    2>/dev/null
tmux select-window -t "${session}:${win_idx}" 2>/dev/null
tmux select-pane   -t "$PANE_ID"    2>/dev/null

# ── detect terminal app from tmux client process tree ─────────────────────────
CLIENT_PID=$(tmux list-clients -t "$session" -F '#{client_pid}' 2>/dev/null | head -1)
TERM_APP=""

if [ -n "$CLIENT_PID" ]; then
  CUR_PID=$CLIENT_PID
  for _ in $(seq 1 10); do
    COMM=$(ps -p "$CUR_PID" -o ucomm= 2>/dev/null | tr -d ' ')
    case "$COMM" in
      alacritty|Alacritty|kitty|WezTerm|wezterm|iTerm2|Terminal|Hyper)
        TERM_APP="$COMM"; break ;;
    esac
    CUR_PID=$(ps -p "$CUR_PID" -o ppid= 2>/dev/null | tr -d ' ')
    [ -z "$CUR_PID" ] || [ "$CUR_PID" = "1" ] && break
  done
fi

if [ -n "$TERM_APP" ]; then
  osascript -e "tell application \"$TERM_APP\" to activate" 2>/dev/null
fi
