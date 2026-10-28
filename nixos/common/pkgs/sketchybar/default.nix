{ lib, sketchybar }:

# Exact patch tested on mac-home/macOS 27.2; do not silently rebase it.
# https://github.com/strayer/SketchyBar/commit/dd43bf67dde4f5f9b31509d3ab85a37158d26777
assert lib.assertMsg (sketchybar.version == "2.24.1")
  "SketchyBar ${sketchybar.version}: review the macOS 27 menu-bar patch before changing its 2.24.1 base";

sketchybar.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./macos27-menu-bar.patch ];
})
