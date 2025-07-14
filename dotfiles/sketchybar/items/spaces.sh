#!/bin/bash

# Workspace configuration matching AwesomeWM's 20 tags
# Creates 20 workspaces (1-10 and 11-20) similar to AwesomeWM setup
# Only shows workspaces with windows opened

SPACE_SIDS=(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20)

for sid in "${SPACE_SIDS[@]}"
do
  sketchybar --add space space.$sid left                                 \
             --set space.$sid space=$sid                                  \
                              icon=$sid                                   \
                              label.font="sketchybar-app-font:Regular:16.0" \
                              label.padding_right=20                     \
                              label.y_offset=-1                          \
                              script="$PLUGIN_DIR/space.sh"              \
                              click_script="aerospace workspace $sid"    \
                              drawing=off
done

# Add workspace monitor that shows/hides spaces based on window presence
sketchybar --add item space_monitor left                               \
           --set space_monitor drawing=off                              \
                               script="$PLUGIN_DIR/space_windows.sh"   \
           --subscribe space_monitor space_windows_change              \
                                     front_app_switched                \
                                     space_change

sketchybar --add item space_separator left                             \
           --set space_separator icon="􀆊"                               \
                                 icon.color=$ACCENT_COLOR              \
                                 icon.padding_left=4                   \
                                 label.drawing=off                     \
                                 background.drawing=off

