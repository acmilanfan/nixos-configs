{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  name = "go-shell";
  buildInputs = with pkgs; [
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
  ];
  shellHook = ''
    export LANG=en_US.UTF-8
    export TZ=Europe/Berlin
    exec zsh
  '';
}
