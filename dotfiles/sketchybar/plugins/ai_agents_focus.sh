#!/bin/bash

# Called when a popup slot is clicked.
# Reads the agent PID, finds its tmux pane, switches to it, and focuses the terminal.
# No Hammerspoon IPC needed — pure shell + tmux + osascript.

SLOT=$(echo "$NAME" | grep -o '[0-9]*$')
PANE_FILE="/tmp/sketchybar_ai_agent_${SLOT}.pane"
[ -f "$PANE_FILE" ] || exit 0
PANE_ID=$(cat "$PANE_FILE" 2>/dev/null)
[ -z "$PANE_ID" ] && exit 0

sketchybar --set ai_agents popup.drawing=off

# ── find tmux session and window from pane_id ────────────────────────────────
read -r session win_idx < <(tmux list-panes -a -F '#{session_name} #{window_index}' -f "#{m:#{pane_id},$PANE_ID}" 2>/dev/null)

if [ -n "$PANE_ID" ]; then
  # Switch tmux to the agent's pane
  tmux switch-client -t "$session"    2>/dev/null
  tmux select-window -t "${session}:${win_idx}" 2>/dev/null
  tmux select-pane   -t "$PANE_ID"    2>/dev/null

  # Bring the terminal to front
  osascript -e 'tell application "Alacritty" to activate' 2>/dev/null
  exit 0
fi
