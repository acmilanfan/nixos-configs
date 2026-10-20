{ pkgs ? import <nixpkgs> {
  overlays = [ (self: super: { jdk = super.jetbrains.jdk; }) ];
} }:

# Manual FHS shell (old behavior), available as `nix develop .#fhs`.
# Its shellHook exec's the FHS shell, so it must not be the default devShell;
# nix-direnv would recurse while loading it.

let
  # selectedJDK = pkgs.openjdk11;
  selectedJDK = pkgs.openjdk21;
  # selectedJDK = pkgs.openjdk23;

  fhs = pkgs.buildFHSEnv {
    name = "java-maven-env";
    targetPkgs = pkgs:
      (with pkgs; [
        maven
        zlib
        pam
        gdb
        libxext
        libx11
        libxrender
        libxtst
        libxi
        freetype
        gradle
        libaio
        numactl
        ncurses5
        libxcrypt
        libxcrypt-legacy
        nodejs_22
        mocha
        typescript
        docker
        openssl
        glibc
        mariadb.client
        glibcLocales
        gnumake
        mariadb
        systemd
      ]);
    runScript = "zsh";
  };

in pkgs.stdenv.mkDerivation {
  name = "maven-shell";
  nativeBuildInputs = [ fhs ];
  shellHook = ''
    export LANG=en_US.UTF-8
    export TZ=Europe/Berlin
    export PATH=$PATH:/run/current-system/bin
    export DOCKER_CONFIG=/etc/docker/config.json
    # Docker access goes through the "docker" group (or rootless Docker, whose
    # NixOS module sets DOCKER_HOST), never a world-writable socket: the old
    # `chmod 666` made the daemon root-equivalent for every local user.
    # A host needs `virtualisation.docker.enable = true;` (socket-activated,
    # so no manual start) and the user in `extraGroups = [ "docker" ]`.
    export DOCKER_HOST="''${DOCKER_HOST:-unix:///var/run/docker.sock}"
    if [ ! -w "''${DOCKER_HOST#unix://}" ]; then
      echo "docker: ''${DOCKER_HOST#unix://} is missing or not writable; enable" \
        "virtualisation.docker and add yourself to the docker group" >&2
    fi

    export JAVA_HOME=${selectedJDK}
    export PATH=$JAVA_HOME/bin:$PATH

    exec java-maven-env
  '';
}
