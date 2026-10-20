{ pkgs ? import <nixpkgs> { } }:

# Manual FHS shell (old behavior), kept for cases that need an FHS root.
# Do not use this as the default devShell: its shellHook exec's a new shell,
# which makes nix-direnv recurse. The default is the plain mkShell in
# nix-go-node.nix.
let
  fhs = pkgs.buildFHSEnv {
    name = "dev-env";
    targetPkgs = pkgs:
      (with pkgs; [
        go
        nodejs
        yarn
        sqlc
        gofumpt
        goimports-reviser
        jq
        python3
        supabase-cli
        go-mockery
      ]);
    runScript = "zsh";
  };
in pkgs.stdenv.mkDerivation {
  name = "go-shell-fhs";
  nativeBuildInputs = [ fhs ];
  shellHook = ''
    export LANG=en_US.UTF-8
    export TZ=Europe/Berlin
    exec dev-env
  '';
}
