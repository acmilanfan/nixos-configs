{ pkgs ? import <nixpkgs> {} }:

let 
  fhs = pkgs.buildFHSEnv {
  name = "dev-env";
  targetPkgs = pkgs: (with pkgs;
    [
      go nodejs yarn sqlc gofumpt goimports-reviser jq
    ]);
    runScript = "zsh";
  };
in pkgs.stdenv.mkDerivation {
  name = "go-shell";
  nativeBuildInputs = [ fhs ];
  shellHook = ''
    export LANG=en_US.UTF-8
    export TZ=Europe/Berlin
    exec dev-env
  '';
}
