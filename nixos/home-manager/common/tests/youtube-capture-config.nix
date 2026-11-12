{ nixpkgsPath, home }:
let
  basePkgs = import nixpkgsPath { system = "aarch64-darwin"; };
  evaluate = isDarwin:
    let
      pkgs = basePkgs // {
        stdenv = basePkgs.stdenv // { inherit isDarwin; };
        youtube-org = "${home}/nix-package";
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
    in {
      configText = module.programs.newsboat.extraConfig;
      includesHelper = builtins.elem pkgs.youtube-org module.home.packages;
    };
in { darwin = evaluate true; linux = evaluate false; }
