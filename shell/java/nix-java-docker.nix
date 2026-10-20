{
  pkgs ? import <nixpkgs> {
    overlays = [ (self: super: { jdk = super.jetbrains.jdk; }) ];
  },
}:

# direnv-friendly default shell. The old FHS shell (including its Docker
# startup hook and `exec java-maven-env`) lives in nix-java-docker-fhs.nix
# and is available as `nix develop .#fhs`. Never `exec` a shell from a
# shellHook: nix-direnv evaluates it while loading the environment.
let
  # selectedJDK = pkgs.openjdk11;
  selectedJDK = pkgs.openjdk21;
  # selectedJDK = pkgs.openjdk23;
in
pkgs.mkShell {
  name = "maven-shell";
  buildInputs =
    with pkgs;
    [
      selectedJDK
      maven
      zlib
      libxext
      libx11
      libxrender
      libxtst
      libxi
      freetype
      gradle
      ncurses5
      libxcrypt
      nodejs_22
      mocha
      typescript
      docker
      openssl
      mariadb.client
      gnumake
      mariadb
    ]
    # Linux-only (macOS uses shell/java/darwin, but keep this evaluable there).
    ++ lib.optionals stdenv.isLinux [
      pam
      gdb
      libaio
      numactl
      libxcrypt-legacy
      glibc
      glibcLocales
    ];
  shellHook = ''
    export LANG=en_US.UTF-8
    export TZ=Europe/Berlin
    export DOCKER_CONFIG=/etc/docker/config.json
    export DOCKER_HOST=unix:///var/run/docker.sock

    export JAVA_HOME=${selectedJDK}
    export PATH="$JAVA_HOME/bin:$PATH"

    # No Docker startup here (nix-direnv runs this hook on every load). The
    # Docker socket needs a host with virtualisation.docker enabled and the
    # user in the "docker" group; see nix-java-docker-fhs.nix.
  '';
}
