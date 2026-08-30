{
  pkgs ? import <nixpkgs> { },
}:

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
    golangci-lint
    docker
    colima
  ];
  shellHook = ''
    export LANG=en_US.UTF-8
    export TZ=Europe/Berlin

    # Docker/Colima env for testcontainers - static exports only.
    # nix-direnv re-runs this hook on EVERY shell load (each new tmux
    # window), so no `colima status` RPC / echoes here - they made every
    # window start noticeably slow. Docker just errors normally if colima
    # is down; check with `colima status` manually when in doubt.
    export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
    export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE="/var/run/docker.sock"
    export TESTCONTAINERS_RYUK_DISABLED="false"
    export TESTCONTAINERS_HOST_OVERRIDE="127.0.0.1"
  '';
}
