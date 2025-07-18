#!/bin/bash

# Maccy configuration script
# Run this after installing Maccy to configure it similar to greenclip

# Set Maccy preferences
defaults write org.p0deje.Maccy historySize -int 200
defaults write org.p0deje.Maccy imageMaxHeight -int 40
defaults write org.p0deje.Maccy enabledPasteboardTypes -array "public.utf8-plain-text" "public.html" "public.rtf"
defaults write org.p0deje.Maccy hideSearch -bool false
defaults write org.p0deje.Maccy hideTitle -bool false
defaults write org.p0deje.Maccy maxMenuItems -int 20
defaults write org.p0deje.Maccy menuIcon -string "clipboard"
defaults write org.p0deje.Maccy pasteByDefault -bool true
defaults write org.p0deje.Maccy removeFormattingByDefault -bool false
defaults write org.p0deje.Maccy showInStatusBar -bool true
defaults write org.p0deje.Maccy showRecentCopyInMenuBar -bool false
defaults write org.p0deje.Maccy sortBy -string "lastCopiedAt"
defaults write org.p0deje.Maccy fuzzySearch -bool true

# Set global hotkey to Alt+Shift+V (matching AwesomeWM)
# Note: This needs to be set manually in Maccy preferences
# as it requires accessibility permissions

echo "Maccy configuration applied!"
echo "Please manually set the global hotkey to Alt+Shift+V in Maccy preferences."
echo "Go to Maccy > Preferences > General > Global hotkey"

