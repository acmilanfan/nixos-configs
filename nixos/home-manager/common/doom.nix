{ pkgs, config, lib, ... }: {

  # imports = [ inputs.nix-doom-emacs.hmModule ];
  #
  programs.emacs = {
    enable = true;
    # doomPrivateDir = ./../../../dotfiles/doom.d;
  };

  # home.file.".doom.d" = {
  #   source = ./../../../dotfiles/doom.d;
  #   recursive = true;
  #   onChange = readFile path/to/reload;
  # };

  services.emacs.enable = true;
  home = {
    sessionPath = [ "${config.xdg.configHome}/emacs/bin" ];
    sessionVariables = {
      DOOMDIR = "${config.xdg.configHome}/doom-config";
      DOOMLOCALDIR = "${config.xdg.configHome}/doom-local";
    };
  };

  xdg = {
    enable = true;
    configFile = {
      "doom-config/config.el".source = ./../../../dotfiles/doom.d/config.el;
      "doom-config/init.el".source = ./../../../dotfiles/doom.d/init.el;
      "doom-config/packages.el".source = ./../../../dotfiles/doom.d/packages.el;
      "emacs" = {
        source = builtins.fetchGit "https://github.com/hlissner/doom-emacs";
        onChange = "${pkgs.writeShellScript "doom-change" ''
          export DOOMDIR="${config.home.sessionVariables.DOOMDIR}"
          export DOOMLOCALDIR="${config.home.sessionVariables.DOOMLOCALDIR}"
          if [ ! -d "$DOOMLOCALDIR" ]; then
            ${config.xdg.configHome}/emacs/bin/doom install
          else
            ${config.xdg.configHome}/emacs/bin/doom sync -u
          fi
        ''}";
      };
    };
  };

  home.packages = with pkgs; [
    # DOOM Emacs dependencies
    binutils
    (ripgrep.override { withPCRE2 = true; })
    gnutls
    fd
    imagemagick
    zstd
    nodePackages.javascript-typescript-langserver
    sqlite
    editorconfig-core-c
    emacs-all-the-icons-fonts
  ];

}
