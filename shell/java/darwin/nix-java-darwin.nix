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
    nodePackages.mocha
    # nodePackages.ts-node
    nodePackages.typescript

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

    # Docker/Colima configuration for testcontainers
    if command -v colima &> /dev/null; then
      if colima status &> /dev/null; then
        echo "Colima is running, configuring testcontainers environment..."
        if [ -x "$HOME/.local/bin/colima-testcontainers-env" ]; then
          eval "$($HOME/.local/bin/colima-testcontainers-env)"
        else
          # Fallback: set basic environment variables
          export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
          export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE="/var/run/docker.sock"
          export TESTCONTAINERS_RYUK_DISABLED="false"
          # Try to get colima IP for TESTCONTAINERS_HOST_OVERRIDE
          COLIMA_IP=$(colima ls -j 2>/dev/null | jq -r '.address // empty')
          if [ -n "$COLIMA_IP" ]; then
            export TESTCONTAINERS_HOST_OVERRIDE="$COLIMA_IP"
            echo "Testcontainers HOST_OVERRIDE set to: $COLIMA_IP"
          fi
        fi
        echo "Docker is configured with colima"
      else
        echo "⚠️  Colima is not running. Start it with: colima start --cpu 4 --memory 8 --disk 60 --network-address"
        echo "   Then restart this shell or run: eval \"\$(colima-testcontainers-env)\""
      fi
    else
      echo "⚠️  Colima not found. Please install colima for Docker support."
    fi

    echo ""
    echo "Java Maven Darwin Development Shell"
    echo "Java version: $(java -version 2>&1 | head -n 1)"
    echo "Maven version: $(mvn -version 2>&1 | head -n 1)"
    echo "Node.js version: $(node --version)"

    # Start zsh
    exec zsh
  '';
}
