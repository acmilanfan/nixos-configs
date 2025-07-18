#!/bin/bash

# Mission Control Space Indicators (based on FelixKratz defaults)
# Creates spaces similar to the official SketchyBar configuration

SPACE_ICONS=("1" "2" "3" "4" "5" "6" "7" "8" "9" "10")

for i in "${!SPACE_ICONS[@]}"
do
  sid="$(($i+1))"
  space=(
    space="$sid"
    icon="${SPACE_ICONS[i]}"
    icon.padding_left=7
    icon.padding_right=7
    background.color=$SPACE_ACTIVE
    background.corner_radius=5
    background.height=25
    label.drawing=off
    script="$PLUGIN_DIR/space.sh"
    click_script="aerospace workspace $sid"
  )
  sketchybar --add space space."$sid" left --set space."$sid" "${space[@]}"
done

# Add workspace monitor that shows/hides spaces based on window presence
sketchybar --add item space_monitor left                               \
           --set space_monitor drawing=off                              \
                               script="$PLUGIN_DIR/space_windows.sh"   \
           --subscribe space_monitor space_windows_change              \
                                     front_app_switched                \
                                     space_change

# Add chevron separator (like in official config)
sketchybar --add item chevron left \
           --set chevron icon= \
                         label.drawing=off

