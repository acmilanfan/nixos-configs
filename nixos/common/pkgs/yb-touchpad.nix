{
  lib,
  rustPlatform,
  pkg-config,
  gtk4,
  glib,
  gtk4-layer-shell,
}:

rustPlatform.buildRustPackage {
  pname = "yb-touchpad";
  version = "0.1.0";

  src = ../../../apps/yb-touchpad;

  cargoLock.lockFile = ../../../apps/yb-touchpad/Cargo.lock;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ gtk4 glib gtk4-layer-shell ];

  meta = {
    description = "Yoga Book 9i on-demand touchpad window (triple-tap on the bottom screen)";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
