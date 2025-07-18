{ pkgs, lib, ... }:

lib.mkIf pkgs.stdenv.isDarwin {
  # Link AeroSpace configuration
  home.file.".config/aerospace/aerospace.toml".source = ../../../dotfiles/aerospace/aerospace.toml;
}
