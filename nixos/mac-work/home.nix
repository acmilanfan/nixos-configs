{ pkgs, lib, ... }:

{
  home.username = "andreishumailov";
  home.homeDirectory = lib.mkForce "/Users/andreishumailov";

  imports = [
    # Import common configurations with macOS guards
    ../home-manager/common/default.nix
  ];

  # macOS-specific packages
  home.packages = with pkgs; [
    # macOS-specific utilities
    mas # Mac App Store CLI
    m-cli # Swiss Army Knife for macOS

    # Development tools that work well on macOS
    colima # Container runtime for macOS

    # Additional macOS tools
    duti # Default application handler
  ] ++ lib.optionals pkgs.stdenv.isDarwin [
    # Darwin-specific packages
  ];

  # macOS-specific shell aliases
  programs.zsh.shellAliases = pkgs.lib.mkMerge [
    {
      # macOS-specific aliases
      sup = "darwin-rebuild switch --flake $HOME/configs/nixos-configs/#mac-work";
      hup = "home-manager switch --flake $HOME/configs/nixos-configs/#andreishumailov@work";

      # macOS system management
      flush-dns = "sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder";
      show-hidden = "defaults write com.apple.finder AppleShowAllFiles -bool true && killall Finder";
      hide-hidden = "defaults write com.apple.finder AppleShowAllFiles -bool false && killall Finder";

      # Docker/Colima shortcuts
      docker-start = "colima start";
      docker-stop = "colima stop";
    }
  ];

  # macOS-specific programs configuration
  programs.git = {
    extraConfig = {
      # macOS-specific git settings
      credential.helper = "osxkeychain";
    };
  };

  # macOS-specific home files
  home.file = {
    # macOS-specific dotfiles can go here
    ".hushlogin".text = ""; # Suppress login message
  };

  # macOS-specific environment variables
  home.sessionVariables = {
    # macOS-specific environment
    BROWSER = "open";
  };

  home.stateVersion = "25.05";
}
