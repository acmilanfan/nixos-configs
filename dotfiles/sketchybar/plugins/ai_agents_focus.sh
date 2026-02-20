#!/bin/bash

# Called when a popup slot is clicked.
# Reads the agent PID, finds its tmux pane, switches to it, and focuses the terminal.
# No Hammerspoon IPC needed — pure shell + tmux + osascript.

SLOT=$(echo "$NAME" | grep -o '[0-9]*$')
PID_FILE="/tmp/sketchybar_ai_agent_${SLOT}.pid"
[ -f "$PID_FILE" ] || exit 0
AGENT_PID=$(cat "$PID_FILE" 2>/dev/null)
[ -z "$AGENT_PID" ] && exit 0

sketchybar --set ai_agents popup.drawing=off

# ── build ancestor set ──────────────────────────────────────────────────────
ancestors="$AGENT_PID"
cur="$AGENT_PID"
for _ in $(seq 1 25); do
  p=$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d ' ')
  [ -z "$p" ] || [ "$p" = "1" ] || [ "$p" = "0" ] && break
  ancestors="$ancestors $p"
  cur="$p"
done

# ── find matching tmux pane ──────────────────────────────────────────────────
pane_id=""
session=""
win_idx=""
while read -r pane_pid pid_id sess w_idx; do
  for anc in $ancestors; do
    if [ "$pane_pid" = "$anc" ]; then
      pane_id="$pid_id"
      session="$sess"
      win_idx="$w_idx"
      break 2
    fi
  done
done < <(tmux list-panes -a -F '#{pane_pid} #{pane_id} #{session_name} #{window_index}' 2>/dev/null)

if [ -n "$pane_id" ]; then
  # Switch tmux to the agent's pane
  tmux switch-client -t "$session"    2>/dev/null
  tmux select-window -t "${session}:${win_idx}" 2>/dev/null
  tmux select-pane   -t "$pane_id"    2>/dev/null

  # Bring the terminal to front (Alacritty is the terminal in use)
  osascript -e 'tell application "Alacritty" to activate' 2>/dev/null
  exit 0
fi

# ── fallback: no tmux, just raise whatever terminal owns the process ─────────
osascript -e 'tell application "Alacritty" to activate' 2>/dev/null
