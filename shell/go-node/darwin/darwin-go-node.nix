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
  ];
  shellHook = ''
    export LANG=en_US.UTF-8
    export TZ=Europe/Berlin

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

    exec zsh
  '';
}
