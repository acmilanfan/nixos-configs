{ pkgs, ... }:

{
  home.username = "andreishumailov";
  home.homeDirectory = "/Users/andreishumailov";

  imports = [
    # TODO adjst and put guards on linux specific
    ../home-manager/common/default.nix
    # Add more as needed
    # ../home-manager/common/neovim.nix
    # ../home-manager/common/tmux.nix
    # etc.
  ];

  # macOS-specific Home Manager options
  # programs.zsh.enable = true;

  # Example: only enable some modules on macOS
  # (You can use pkgs.stdenv.isDarwin inside modules for finer control)
}
