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
  buildInputs = with pkgs; [
    selectedJDK
    maven
    zlib
    pam
    gdb
    xorg.libXext
    xorg.libX11
    xorg.libXrender
    xorg.libXtst
    xorg.libXi
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
  ];
  shellHook = ''
    export LANG=en_US.UTF-8
    export TZ=Europe/Berlin
    export DOCKER_CONFIG=/etc/docker/config.json
    export DOCKER_HOST=unix:///var/run/docker.sock

    export JAVA_HOME=${selectedJDK}
    export PATH="$JAVA_HOME/bin:$PATH"

    # The FHS shell started Docker with sudo on entry. Do not do that from
    # direnv (it would run on every prompt); use `nix develop .#fhs` or start
    # it manually with `sudo systemctl start docker`.
  '';
}
