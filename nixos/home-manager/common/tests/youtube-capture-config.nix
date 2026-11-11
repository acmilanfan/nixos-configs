{ nixpkgsPath, home }:
let
  basePkgs = import nixpkgsPath { system = "aarch64-darwin"; };
  evaluate = isDarwin:
    let
      pkgs = basePkgs // {
        stdenv = basePkgs.stdenv // { inherit isDarwin; };
        # Capture the generated script body without building unrelated packages.
        writeShellScript = name: text: builtins.toFile name (
          if name == "newsboat-youtube-notify" then
            ''printf '%s' "$1" > ${basePkgs.lib.escapeShellArg "${home}/notification"}''
          else text
        );
      };
      module = import ../rss.nix {
        inherit pkgs;
        lib = basePkgs.lib;
        config.home.homeDirectory = home;
      };
    in module.programs.newsboat.extraConfig;
in { darwin = evaluate true; linux = evaluate false; }
