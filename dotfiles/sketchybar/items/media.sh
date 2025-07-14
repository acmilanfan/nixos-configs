#!/bin/bash

# Media widget for music/video controls

sketchybar --add item media right \
           --set media icon=$SPOTIFY_PLAY_PAUSE \
                       icon.color=$PURPLE \
                       label.color=$LABEL_COLOR \
                       label.max_chars=20 \
                       scroll_texts=on \
                       script="$PLUGIN_DIR/media.sh" \
           --subscribe media media_change

