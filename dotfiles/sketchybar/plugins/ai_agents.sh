#!/bin/bash

# ═══════════════════════════════════════════════════════════════
# ai_agents.sh — AI Coding Assistant Session Monitor
#
# Pane detection/classification is shared via ai-agent-list; this script
# only handles sketchybar-specific presentation (popup slots, counters).
# ═══════════════════════════════════════════════════════════════

MAX_SLOTS=8

# Close popup on mouse.exited.global (auto-fired when leaving bar)
if [ "$SENDER" = "mouse.exited.global" ]; then
  sketchybar --set "$NAME" popup.drawing=off
  exit 0
fi

AGENT_ROWS=$(ai-agent-list)

if [ -z "$AGENT_ROWS" ]; then
  sketchybar --set "$NAME" drawing=off background.drawing=off popup.drawing=off
  exit 0
fi

SLOT=0
# Priority: idle=0 < done=1 < running=2 < needs-input=3
AGG_PRIORITY=0
AGGREGATE="idle"
CLAUDE_ACTIVE=0
GEMINI_ACTIVE=0
ANTIGRAVITY_ACTIVE=0
OPENCODE_ACTIVE=0

update_aggregate() {
  local priority="$1" state="$2"
  if [ "$priority" -gt "$AGG_PRIORITY" ]; then
    AGG_PRIORITY=$priority
    AGGREGATE="$state"
  fi
}

while IFS='|' read -r pane_id status type project cwd; do
  [ -z "$pane_id" ] && continue
  SLOT=$((SLOT + 1))
  [ "$SLOT" -gt "$MAX_SLOTS" ] && break

  TYPE="${type:0:1}"

  DOT="" COLOR=""
  case "$status" in
    needs-input)
      DOT="●"; COLOR="0xffe06c75"   # red — needs input
      update_aggregate 3 "confirm"
      ;;
    running)
      DOT="●"; COLOR="0xffe0af68"   # yellow — working
      update_aggregate 2 "working"
      ;;
    done)
      DOT="●"; COLOR="0xff7b5cff"   # purple — waiting/recent
      update_aggregate 1 "recent"
      ;;
    idle)
      DOT="○"; COLOR="0xff565f89"   # gray — idle
      ;;
  esac

  [[ "$TYPE" == "C" ]] && CLAUDE_ACTIVE=$((CLAUDE_ACTIVE + 1))
  [[ "$TYPE" == "G" ]] && GEMINI_ACTIVE=$((GEMINI_ACTIVE + 1))
  [[ "$TYPE" == "A" ]] && ANTIGRAVITY_ACTIVE=$((ANTIGRAVITY_ACTIVE + 1))
  [[ "$TYPE" == "O" ]] && OPENCODE_ACTIVE=$((OPENCODE_ACTIVE + 1))

  echo "$pane_id" > "/tmp/sketchybar_ai_agent_${SLOT}.pane"
  sketchybar --set "ai_agents.popup.${SLOT}" drawing=on icon="$DOT" icon.color="$COLOR" label="${TYPE}: $project"
done <<< "$AGENT_ROWS"

# Hide unused slots and clear their PANE files
i=$((SLOT + 1))
while [ "$i" -le "$MAX_SLOTS" ]; do
  sketchybar --set "ai_agents.popup.${i}" drawing=off
  rm -f "/tmp/sketchybar_ai_agent_${i}.pane"
  i=$((i + 1))
done

# ──────────────────────────────────────────────────────────────
# Update bar item (count + aggregate color)
# ──────────────────────────────────────────────────────────────

LABEL=""
[ "$CLAUDE_ACTIVE" -gt 0 ] && LABEL="C:${CLAUDE_ACTIVE}"
[ "$GEMINI_ACTIVE" -gt 0 ] && LABEL="${LABEL:+$LABEL }G:${GEMINI_ACTIVE}"
[ "$ANTIGRAVITY_ACTIVE" -gt 0 ] && LABEL="${LABEL:+$LABEL }A:${ANTIGRAVITY_ACTIVE}"
[ "$OPENCODE_ACTIVE" -gt 0 ] && LABEL="${LABEL:+$LABEL }O:${OPENCODE_ACTIVE}"

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
