#!/bin/bash

# Icon mapping for applications

case "$1" in
"Finder") echo "􀈕";;
"Safari") echo "􀎭";;
"Firefox") echo "􀤆";;
"Google Chrome") echo "􀤆";;
"Terminal") echo "􀆍";;
"Alacritty") echo "􀆍";;
"Kitty") echo "􀆍";;
"Code") echo "􀤙";;
"Xcode") echo "􀤘";;
"System Preferences") echo "􀺽";;
"Activity Monitor") echo "􀒓";;
"Calculator") echo "􀖩";;
"Calendar") echo "􀉉";;
"Mail") echo "􀍕";;
"Messages") echo "􀌤";;
"Music") echo "􀑪";;
"Spotify") echo "􀑪";;
"Slack") echo "􀌤";;
"Discord") echo "􀌤";;
*) echo "􀏜";;
esac

