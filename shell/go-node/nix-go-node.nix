{
  pkgs ? import <nixpkgs> { },
}:

# direnv-friendly default shell. The FHS variant lives in
# nix-go-node-fhs.nix and is available as `nix develop .#fhs`; a shellHook
# must never `exec` another shell, because nix-direnv evaluates it while
# loading the environment.
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
  '';
}
