{ pkgs ? import <nixpkgs> { } }:

let
  # selectedJDK = pkgs.openjdk11;
  selectedJDK = pkgs.openjdk21;
  # selectedJDK = pkgs.openjdk23;

in pkgs.mkShell {
  name = "java-maven-darwin-shell";

  buildInputs = with pkgs; [
    # Java and build tools
    selectedJDK
    maven
    gradle

    # Node.js ecosystem
    nodejs
    mocha
    typescript

    # Development tools
    openssl
    gnumake

    # Database clients
    mariadb.client
    redis

    # Docker CLI (works with colima)
    docker

    # Shell
    zsh

    # macOS-compatible utilities
    zlib
    freetype
    ncurses
  ];

  shellHook = ''
    export LANG=en_US.UTF-8
    export TZ=Europe/Berlin

    # Java configuration
    export JAVA_HOME=${selectedJDK}
    export PATH=$JAVA_HOME/bin:$PATH

    # macOS-specific PATH additions
    export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"

    # Docker/Colima env for testcontainers - static exports only.
    # nix-direnv re-runs this hook on EVERY shell load (each new tmux
    # window), so no `colima status` RPC / JVM-spawning version banners
    # here - they made every window start noticeably slow. Check versions
    # manually when needed; docker just errors normally if colima is down.
    export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
    export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE="/var/run/docker.sock"
    export TESTCONTAINERS_RYUK_DISABLED="false"
    export TESTCONTAINERS_HOST_OVERRIDE="127.0.0.1"
  '';
}
