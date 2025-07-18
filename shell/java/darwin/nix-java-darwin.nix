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
    nodejs_22
    nodePackages.mocha
    nodePackages.ts-node
    nodePackages.typescript

    # Development tools
    openssl
    gnumake

    # Database clients
    mysql-client
    mariadb

    # Docker for macOS (Docker Desktop should be installed separately)
    # docker

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

    # Docker configuration for macOS
    # Note: Docker Desktop should be running
    if command -v docker &> /dev/null; then
      if docker info &> /dev/null; then
        echo "Docker is running"
      else
        echo "Docker Desktop is not running. Please start Docker Desktop."
      fi
    else
      echo "Docker not found. Please install Docker Desktop for macOS."
    fi

    # macOS-specific PATH additions
    export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"
    # export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"

    echo "Java Maven Darwin Development Shell"
    echo "Java version: $(java -version 2>&1 | head -n 1)"
    echo "Maven version: $(mvn -version 2>&1 | head -n 1)"
    echo "Node.js version: $(node --version)"

    # Start zsh
    exec zsh
  '';
}
